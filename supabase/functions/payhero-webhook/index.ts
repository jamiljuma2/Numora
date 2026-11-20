const PAYHERO_STATUS_URL = 'https://backend.payhero.co.ke/api/v2/transaction-status';

type PayHeroCallback = {
  response?: {
    Amount?: number | string;
    ExternalReference?: string;
    MpesaReceiptNumber?: string | null;
    ResultCode?: number;
    ResultDesc?: string;
    Status?: string;
  };
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const payheroUsername = Deno.env.get('PAYHERO_API_USERNAME');
  const payheroPassword = Deno.env.get('PAYHERO_API_PASSWORD');
  if (!supabaseUrl || !serviceKey || !payheroUsername || !payheroPassword) {
    console.error('payhero_webhook_configuration_missing');
    return json({ error: 'Payment verification is not configured.' }, 503);
  }

  let callback: PayHeroCallback;
  try {
    callback = await request.json();
  } catch {
    return json({ error: 'Invalid JSON callback.' }, 400);
  }

  const payload = callback.response;
  const reference = payload?.ExternalReference;
  const amount = Number(payload?.Amount);
  if (!reference || !/^NUM-[A-F0-9]{20}$/.test(reference) || !Number.isFinite(amount) || amount <= 0) {
    return json({ error: 'Invalid payment callback.' }, 400);
  }

  const restHeaders = {
    apikey: serviceKey,
    authorization: `Bearer ${serviceKey}`,
    'content-type': 'application/json',
  };
  const lookup = new URL('/rest/v1/payment_provider_transactions', supabaseUrl);
  lookup.searchParams.set('select', 'provider_reference');
  lookup.searchParams.set('provider', 'eq.payhero');
  lookup.searchParams.set('external_reference', `eq.${reference}`);

  let providerReference: string | null;
  try {
    const lookupResponse = await fetch(lookup, { headers: restHeaders });
    if (!lookupResponse.ok) throw new Error(`Supabase lookup failed (${lookupResponse.status})`);
    const rows = await lookupResponse.json();
    providerReference = rows?.[0]?.provider_reference ?? null;
  } catch (error) {
    console.error('payhero_reference_lookup_failed', error);
    return json({ error: 'Payment reference could not be checked. Retry the callback.' }, 503);
  }
  if (!providerReference) return json({ error: 'Payment reference is not ready for verification.' }, 503);

  const auth = btoa(`${payheroUsername}:${payheroPassword}`);
  const statusUrl = new URL(PAYHERO_STATUS_URL);
  statusUrl.searchParams.set('reference', providerReference);
  let verified: { status?: string; reference?: string };
  try {
    const statusResponse = await fetch(statusUrl, { headers: { authorization: `Basic ${auth}` } });
    if (!statusResponse.ok) throw new Error(`PayHero status lookup failed (${statusResponse.status})`);
    verified = await statusResponse.json();
  } catch (error) {
    console.error('payhero_status_lookup_failed', error);
    return json({ error: 'PayHero could not verify this payment. Retry the callback.' }, 503);
  }

  const verifiedStatus = verified.status?.toUpperCase();
  if (verified.reference !== providerReference || !['SUCCESS', 'FAILED'].includes(verifiedStatus ?? '')) {
    return json({ ok: true, status: verified.status ?? 'PENDING' }, 202);
  }

  const resultCode = Number(payload?.ResultCode);
  const callbackStatus = payload?.Status?.toLowerCase() ?? '';
  const resultDescription = payload?.ResultDesc?.toLowerCase() ?? '';
  const cancelledByCustomer = resultCode === 1032 ||
    callbackStatus === 'cancelled' || callbackStatus === 'canceled' ||
    resultDescription.includes('cancelled') || resultDescription.includes('canceled');
  const outcome = verifiedStatus === 'SUCCESS'
    ? 'completed'
    : cancelledByCustomer ? 'cancelled' : 'failed';

  const processResponse = await fetch(new URL('/rest/v1/rpc/process_payhero_callback', supabaseUrl), {
    method: 'POST',
    headers: { ...restHeaders, prefer: 'return=minimal' },
    body: JSON.stringify({
      p_reference: reference,
      p_amount_minor: Math.round(amount * 100),
      p_outcome: outcome,
      p_provider_reference: payload?.MpesaReceiptNumber ?? null,
      p_payload: { callback: payload, verification: verified },
    }),
  });

  if (!processResponse.ok) {
    console.error('payhero_callback_processing_failed', processResponse.status, await processResponse.text());
    return json({ error: 'Payment callback could not be processed. Retry the callback.' }, 503);
  }
  return json({ ok: true, status: outcome });
});

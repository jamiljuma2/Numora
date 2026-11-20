# Payments

## PayHero M-Pesa deposits

The API uses `POST https://backend.payhero.co.ke/api/v2/payments` with HTTP Basic authentication, integer KES amount, phone number, channel ID, `provider: "m-pesa"`, a unique external reference, and callback URL. A successful request creates a pending deposit; it never credits the wallet.

PayHero's callback is treated as an untrusted notification. It is sent directly to the Supabase Edge Function at `https://rvmxonjgotrzdocdkpcj.supabase.co/functions/v1/payhero-webhook` (the project reference is the hostname prefix). The function resolves `ExternalReference` to the stored PayHero reference, asks PayHero's authenticated `GET /api/v2/transaction-status?reference=...` endpoint for the transaction state, then calls a database function. The database locks the deposit and wallet, checks the amount and pending state, updates the ledger and balance atomically, and makes duplicate callbacks harmless.

PayHero's currently published docs show callback fields but do not specify a callback signature. The endpoint therefore relies on server-to-server transaction status verification rather than a fabricated signature convention. If PayHero provides an account-specific callback signing mechanism, add its documented validation before production.

When PayHero verifies a failed STK request, the callback is classified as `cancelled` if its result code is `1032` or the callback status/description explicitly says cancelled. The deposit and transaction rows are then updated atomically from `pending` to `cancelled`. Other verified unsuccessful payments become `failed`.

## Configuration

The Node API derives `callback_url` from `SUPABASE_URL`; the required format is `https://<project-ref>.supabase.co`. Deploy `supabase/functions/payhero-webhook` with `supabase functions deploy payhero-webhook`. The function has `verify_jwt = false` because PayHero cannot send a Supabase JWT; it verifies callbacks by querying PayHero with server-side credentials.

Set `PAYHERO_API_USERNAME`, `PAYHERO_API_PASSWORD`, and `PAYHERO_CHANNEL_ID` in the backend environment and as Supabase Edge Function secrets. Set `SUPABASE_SERVICE_ROLE_KEY` only in the server environments that need it; Supabase provides a service role secret to Edge Functions. Never put these secrets in frontend variables or a committed `.env.example`.

To configure Edge Function secrets with the Supabase CLI, run `supabase secrets set PAYHERO_API_USERNAME=... PAYHERO_API_PASSWORD=... PAYHERO_CHANNEL_ID=...` using the values from the PayHero account. For local function testing, use `supabase functions serve payhero-webhook` and configure the matching local callback URL only in a PayHero test setup.

## References

- [PayHero STK Push](https://docs.payhero.co.ke/docs/post-initiate-mpesa-stk-push-request)
- [PayHero callback fields](https://docs.payhero.co.ke/docs/payment-callback)
- [PayHero transaction status](https://docs.payhero.co.ke/docs/get-transaction-status)

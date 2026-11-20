create or replace function public.process_payhero_callback(
 p_reference text,
 p_amount_minor bigint,
 p_outcome text,
 p_provider_reference text,
 p_payload jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare
 d public.deposits;
 w public.wallets;
begin
 if p_outcome not in ('completed','failed','cancelled') then raise exception 'Invalid payment outcome'; end if;
 select * into d from public.deposits where reference=p_reference for update;
 if not found then raise exception 'Deposit not found'; end if;
 if d.amount_minor<>p_amount_minor then raise exception 'Payment amount mismatch'; end if;
 update public.payment_provider_transactions
   set payload=p_payload,provider_status=upper(p_outcome)
   where external_reference=p_reference and provider_status not in ('SUCCESS','FAILED','CANCELLED');
 if d.status<>'pending' then return; end if;
 if p_outcome in ('failed','cancelled') then
   update public.deposits set status=p_outcome,updated_at=now() where id=d.id;
   update public.transactions set status=p_outcome where id=d.transaction_id;
   return;
 end if;
 select * into w from public.wallets where user_id=d.user_id and currency=d.currency for update;
 if not found then raise exception 'Wallet not found'; end if;
 update public.wallets set balance_minor=balance_minor+d.amount_minor where id=w.id;
 update public.deposits set status='completed',updated_at=now() where id=d.id;
 update public.transactions set status='completed' where id=d.transaction_id;
 insert into public.wallet_ledger(wallet_id,transaction_id,delta_minor)
   values(w.id,d.transaction_id,d.amount_minor) on conflict(transaction_id) do nothing;
end $$;

revoke all on function public.process_payhero_callback(text,bigint,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.process_payhero_callback(text,bigint,text,text,jsonb) to service_role;

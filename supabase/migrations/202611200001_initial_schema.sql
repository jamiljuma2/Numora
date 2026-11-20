create extension if not exists pgcrypto;
create type public.account_status as enum ('active','suspended','closed');
create type public.tx_status as enum ('pending','completed','failed','cancelled','refunded');
create type public.number_status as enum ('pending','active','suspended','expired','cancelled','released','failed');
create type public.activation_status as enum ('pending','waiting_sms','sms_received','completed','cancelled','expired','failed');
create type public.rental_status as enum ('pending','active','suspended','expired','cancelled');

create table public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', country_code char(2), phone text, avatar_url text,
 status public.account_status not null default 'active', preferred_currency char(3) not null default 'USD',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.user_roles(user_id uuid primary key references auth.users(id) on delete cascade, role text not null default 'customer' check(role in ('customer','support','admin')), created_at timestamptz not null default now());
create table public.wallets(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),currency char(3) not null default 'USD',balance_minor bigint not null default 0 check(balance_minor>=0),status text not null default 'active',created_at timestamptz not null default now(),unique(user_id,currency));
create table public.transactions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),type text not null,amount_minor bigint not null,currency char(3) not null,status public.tx_status not null default 'pending',reference text not null unique,description text,created_at timestamptz not null default now());
create index transactions_user_created_idx on public.transactions(user_id,created_at desc);
create table public.deposits(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),transaction_id uuid references public.transactions(id),reference text not null unique,phone text not null,amount_minor bigint not null check(amount_minor>0),currency char(3) not null default 'KES',status public.tx_status not null default 'pending',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index deposits_pending_idx on public.deposits(status,created_at) where status='pending';
create table public.payment_provider_transactions(id uuid primary key default gen_random_uuid(),deposit_id uuid references public.deposits(id),provider text not null,external_reference text not null,provider_reference text,checkout_request_id text,provider_status text,payload jsonb,created_at timestamptz not null default now(),unique(provider,external_reference));
create table public.wallet_ledger(id uuid primary key default gen_random_uuid(),wallet_id uuid not null references public.wallets(id),transaction_id uuid not null unique references public.transactions(id),delta_minor bigint not null,created_at timestamptz not null default now());

create table public.country_catalog(iso2 char(2) primary key,name text not null,dial_code text not null,flag text,is_enabled boolean not null default false,created_at timestamptz not null default now());
create table public.telecom_providers(id uuid primary key default gen_random_uuid(),name text not null unique,adapter text not null,enabled boolean not null default false,priority int not null default 100,health text not null default 'unknown',created_at timestamptz not null default now());
create table public.provider_credentials(id uuid primary key default gen_random_uuid(),provider_id uuid not null references public.telecom_providers(id),secret_ref text not null,created_at timestamptz not null default now(),unique(provider_id,secret_ref));
create table public.provider_countries(provider_id uuid not null references public.telecom_providers(id),country_code char(2) not null references public.country_catalog(iso2),sms boolean not null default false,voice boolean not null default false,rental boolean not null default false,primary key(provider_id,country_code));
create table public.provider_numbers(id uuid primary key default gen_random_uuid(),provider_id uuid not null references public.telecom_providers(id),provider_number_id text not null,phone_number text not null,country_code char(2) not null references public.country_catalog(iso2),capabilities jsonb not null default '{}',cost_minor bigint,available boolean not null default true,updated_at timestamptz not null default now(),unique(provider_id,provider_number_id));
create table public.number_products(id uuid primary key default gen_random_uuid(),provider_number_id uuid references public.provider_numbers(id),kind text not null check(kind in ('temporary','dedicated','rental')),duration_days int,price_minor bigint not null,currency char(3) not null,enabled boolean not null default true,created_at timestamptz not null default now());
create table public.pricing_rules(id uuid primary key default gen_random_uuid(),country_code char(2) references public.country_catalog(iso2),provider_id uuid references public.telecom_providers(id),product_kind text,markup_percent numeric(8,3) not null default 0,fixed_fee_minor bigint not null default 0,min_margin_minor bigint not null default 0,currency char(3) not null default 'USD',active boolean not null default true,created_at timestamptz not null default now());
create table public.number_purchases(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),provider_number_id uuid references public.provider_numbers(id),phone_number text not null,country_code char(2) not null,provider text not null,price_minor bigint not null,currency char(3) not null,status public.number_status not null default 'pending',created_at timestamptz not null default now());
create table public.number_rentals(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),provider_number_id uuid references public.provider_numbers(id),phone_number text not null,country_code char(2) not null,provider text not null,monthly_price_minor bigint not null,currency char(3) not null,sms_enabled boolean not null default false,voice_enabled boolean not null default false,status public.rental_status not null default 'pending',auto_renew boolean not null default false,renews_at timestamptz,created_at timestamptz not null default now());
create table public.activations(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),provider text not null,provider_activation_id text,phone_number text not null,country_code char(2) not null,service_category text,price_minor bigint not null,currency char(3) not null,status public.activation_status not null default 'pending',expires_at timestamptz,created_at timestamptz not null default now(),unique(provider,provider_activation_id));
create table public.sms_messages(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),activation_id uuid references public.activations(id),rental_id uuid references public.number_rentals(id),provider text not null,provider_message_id text,sender text,receiving_number text not null,content text not null,received_at timestamptz not null default now(),is_read boolean not null default false,deleted_at timestamptz,unique(provider,provider_message_id));
create index sms_messages_user_time_idx on public.sms_messages(user_id,received_at desc);
create table public.provider_webhook_events(id uuid primary key default gen_random_uuid(),provider text not null,event_id text,payload jsonb not null,processed_at timestamptz,created_at timestamptz not null default now(),unique(provider,event_id));
create table public.sms_webhook_events(id uuid primary key default gen_random_uuid(),provider text not null,event_id text,payload jsonb not null,processed_at timestamptz,created_at timestamptz not null default now(),unique(provider,event_id));
create table public.notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),kind text not null,title text not null,body text not null,read_at timestamptz,created_at timestamptz not null default now());
create index notifications_user_idx on public.notifications(user_id,created_at desc);
create table public.support_tickets(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),subject text not null,category text not null,description text not null,priority text not null default 'normal',status text not null default 'open',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.support_ticket_messages(id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.support_tickets(id) on delete cascade,sender_id uuid not null references auth.users(id),body text not null,created_at timestamptz not null default now());
create table public.audit_logs(id uuid primary key default gen_random_uuid(),admin_id uuid references auth.users(id),action text not null,target_type text not null,target_id text,previous_value jsonb,new_value jsonb,ip_address inet,created_at timestamptz not null default now());
create table public.system_settings(key text primary key,value jsonb not null,updated_at timestamptz not null default now());
create table public.currency_rates(base char(3) not null,quote char(3) not null,rate numeric(20,10) not null,source text not null,updated_at timestamptz not null default now(),primary key(base,quote));
create table public.promotions(id uuid primary key default gen_random_uuid(),code text unique not null,discount_percent numeric(5,2),discount_minor bigint,starts_at timestamptz,ends_at timestamptz,enabled boolean not null default false);
create table public.promotion_redemptions(id uuid primary key default gen_random_uuid(),promotion_id uuid not null references public.promotions(id),user_id uuid not null references auth.users(id),transaction_id uuid references public.transactions(id),created_at timestamptz not null default now(),unique(promotion_id,user_id));
create table public.user_sessions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),last_seen_at timestamptz not null default now(),ip_address inet,user_agent text,revoked_at timestamptz);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin
 insert into public.profiles(id,full_name,country_code) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),nullif(new.raw_user_meta_data->>'country',''));
 insert into public.wallets(user_id,currency) values(new.id,'USD');
 insert into public.user_roles(user_id,role) values(new.id,'customer');
 return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.create_pending_deposit(p_user_id uuid,p_amount_minor bigint,p_reference text,p_phone text) returns public.deposits language plpgsql security definer set search_path=public as $$ declare d public.deposits; begin
 if p_amount_minor<10000 or p_amount_minor>15000000 then raise exception 'Invalid deposit amount'; end if;
 insert into public.wallets(user_id,currency) values(p_user_id,'KES') on conflict(user_id,currency) do nothing;
 insert into public.transactions(user_id,type,amount_minor,currency,status,reference,description) values(p_user_id,'deposit',p_amount_minor,'KES','pending',p_reference,'M-Pesa wallet deposit');
 insert into public.deposits(user_id,transaction_id,reference,phone,amount_minor,currency) values(p_user_id,(select id from public.transactions where reference=p_reference),p_reference,p_phone,p_amount_minor,'KES') returning * into d;
 return d; end $$;
create or replace function public.mark_deposit_failed(p_reference text,p_reason text) returns void language plpgsql security definer set search_path=public as $$ begin update public.deposits set status='failed',updated_at=now() where reference=p_reference and status='pending'; update public.transactions set status='failed',description=p_reason where reference=p_reference and status='pending'; end $$;
create or replace function public.process_payhero_callback(p_reference text,p_amount_minor bigint,p_outcome text,p_provider_reference text,p_payload jsonb) returns void language plpgsql security definer set search_path=public as $$ declare d public.deposits; w public.wallets; t public.transactions; begin
 if p_outcome not in ('completed','failed','cancelled') then raise exception 'Invalid payment outcome'; end if;
 select * into d from public.deposits where reference=p_reference for update; if not found then raise exception 'Deposit not found'; end if;
 if d.amount_minor<>p_amount_minor then raise exception 'Payment amount mismatch'; end if;
 update public.payment_provider_transactions set payload=p_payload,provider_status=upper(p_outcome) where external_reference=p_reference and provider_status not in ('SUCCESS','FAILED','CANCELLED');
 if d.status<>'pending' then return; end if;
 if p_outcome in ('failed','cancelled') then update public.deposits set status=p_outcome,updated_at=now() where id=d.id; update public.transactions set status=p_outcome where id=d.transaction_id; return; end if;
 select * into w from public.wallets where user_id=d.user_id and currency=d.currency for update; if not found then raise exception 'Wallet not found'; end if;
 update public.wallets set balance_minor=balance_minor+d.amount_minor where id=w.id;
 update public.deposits set status='completed',updated_at=now() where id=d.id;
 update public.transactions set status='completed' where id=d.transaction_id;
 insert into public.wallet_ledger(wallet_id,transaction_id,delta_minor) values(w.id,d.transaction_id,d.amount_minor) on conflict(transaction_id) do nothing;
end $$;
create or replace function public.dashboard_summary(p_user_id uuid) returns jsonb language sql security definer set search_path=public as $$ select jsonb_build_object('wallet',coalesce((select jsonb_build_object('minor',balance_minor,'currency',currency,'formatted',currency||' '||to_char(balance_minor/100.0,'FM9999999990.00')) from public.wallets where user_id=p_user_id and currency=(select preferred_currency from public.profiles where id=p_user_id)),'{}'::jsonb),'numbers',jsonb_build_object('active',(select count(*) from public.number_purchases where user_id=p_user_id and status='active')),'messages',jsonb_build_object('month',(select count(*) from public.sms_messages where user_id=p_user_id and received_at>=date_trunc('month',now())))); $$;

alter table public.profiles enable row level security; alter table public.user_roles enable row level security; alter table public.wallets enable row level security; alter table public.transactions enable row level security; alter table public.deposits enable row level security; alter table public.wallet_ledger enable row level security; alter table public.number_purchases enable row level security; alter table public.number_rentals enable row level security; alter table public.activations enable row level security; alter table public.sms_messages enable row level security; alter table public.notifications enable row level security; alter table public.support_tickets enable row level security; alter table public.support_ticket_messages enable row level security;
create policy profile_self on public.profiles for select using(id=auth.uid()); create policy profile_update_self on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy roles_self_read on public.user_roles for select using(user_id=auth.uid());
create policy wallet_self_read on public.wallets for select using(user_id=auth.uid());
create policy transactions_self_read on public.transactions for select using(user_id=auth.uid()); create policy deposits_self_read on public.deposits for select using(user_id=auth.uid()); create policy ledger_self_read on public.wallet_ledger for select using(wallet_id in(select id from public.wallets where user_id=auth.uid()));
create policy purchases_self on public.number_purchases for select using(user_id=auth.uid()); create policy rentals_self on public.number_rentals for select using(user_id=auth.uid()); create policy activations_self on public.activations for select using(user_id=auth.uid()); create policy sms_self on public.sms_messages for select using(user_id=auth.uid()); create policy notifications_self on public.notifications for select using(user_id=auth.uid()); create policy notifications_update_self on public.notifications for update using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy tickets_self on public.support_tickets for all using(user_id=auth.uid()) with check(user_id=auth.uid()); create policy ticket_messages_self on public.support_ticket_messages for select using(ticket_id in(select id from public.support_tickets where user_id=auth.uid()));
grant usage on schema public to authenticated; grant select,update on public.profiles to authenticated; grant select on public.user_roles,public.wallets,public.transactions,public.deposits,public.wallet_ledger,public.number_purchases,public.number_rentals,public.activations,public.sms_messages,public.notifications,public.support_tickets,public.support_ticket_messages to authenticated;
revoke all on function public.create_pending_deposit(uuid,bigint,text,text) from public,anon,authenticated;
revoke all on function public.mark_deposit_failed(text,text) from public,anon,authenticated;
revoke all on function public.process_payhero_callback(text,bigint,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.dashboard_summary(uuid) from public,anon,authenticated;
grant execute on function public.create_pending_deposit(uuid,bigint,text,text) to service_role;
grant execute on function public.mark_deposit_failed(text,text) to service_role;
grant execute on function public.process_payhero_callback(text,bigint,text,text,jsonb) to service_role;
grant execute on function public.dashboard_summary(uuid) to service_role;

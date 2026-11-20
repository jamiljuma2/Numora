# Database

Apply SQL migrations in `supabase/migrations` to a new Supabase project. Auth users receive a profile, USD wallet and customer role from the signup trigger. The initial schema includes wallets and ledger, payment/deposit records, provider inventory, purchases, rentals, activations, SMS, notifications, support, pricing, promotions, sessions and audit logs.

Customer-facing tables have row-level security policies. Elevated writes use the backend service role and must be authorized in Express; never expose that key in Vite. Payment ledger mutation is exposed only through server-side database functions and is not granted to the authenticated PostgREST role.

The first migration is an initial schema for a new project. Review the database policies against the exact Supabase setup and add admin-specific audited procedures before enabling administrative access.

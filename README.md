# Numora

Numora is a React + Express foundation for an international virtual-number marketplace. It includes a responsive customer workspace, Supabase Auth wiring, an initial Supabase schema with row-level security, and a PayHero M-Pesa deposit flow that remains disabled until server credentials are configured.

## Development

Requirements: Node.js 20+ and npm.

1. Copy `.env.example` to `.env` and fill in the Supabase project URL and service role key. Keep the service role key server-side.
2. The Vite config reads the workspace root `.env`; the `VITE_` values in that file configure the browser app. In deployment, set those same `VITE_` values in the frontend host's build environment.
3. Apply `supabase/migrations/202611200001_initial_schema.sql` to a new Supabase project.
4. Run `npm install`, then `npm run dev`.
5. Open the Vite URL printed by the frontend server.

Without Supabase, authentication and wallet endpoints return a clear configuration error. Without PayHero credentials, deposits are disabled. Without an authorized telecom adapter, number availability and purchases are disabled. No payments, SMS or numbers are fabricated by the backend.

## PayHero

The callback URL is derived from `SUPABASE_URL` and points to `https://<project-ref>.supabase.co/functions/v1/payhero-webhook`. With the current project reference it resolves to `https://rvmxonjgotrzdocdkpcj.supabase.co/functions/v1/payhero-webhook`. Deploy the Edge Function before initiating payments; no separate `PAYHERO_CALLBACK_URL` variable is needed.

Set `PAYHERO_API_USERNAME`, `PAYHERO_API_PASSWORD`, and `PAYHERO_CHANNEL_ID` as backend environment variables and as Supabase Edge Function secrets. The Edge Function needs these credentials to verify the callback with PayHero.

STK requests use PayHero's documented Basic Auth endpoint. Callbacks are treated as notifications and checked against PayHero's authenticated transaction-status API before wallet crediting. Amount, unique reference, pending status, and a locked wallet row are checked in the database transaction. Confirm callback behavior and production credentials with PayHero before go-live. The API documentation currently describes callback fields but does not document a callback signing header, so the implementation does not assume one.

See [docs/PAYMENTS.md](docs/PAYMENTS.md).

## Deployment outline

- Frontend: deploy `frontend/` to Vercel. Production API URL: `https://numora-1.onrender.com/api`; set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Vercel as **Config** variables (all `VITE_*` values are included in the browser bundle). Keep service-role and PayHero credentials only on the backend host as **Secret** variables.
- API: deployed at `https://numora-1.onrender.com`; set `FRONTEND_URL=https://frontend-woad-six-10.vercel.app` in Render and configure server secrets.
- Database: create Supabase project, apply migrations, enable email verification and configure allowed redirect URLs.
- Webhooks: configure the public HTTPS API URL in PayHero and any authorized telecom provider.
- Operations: use provider dashboards for reconciliation, configure backups and database PITR, and monitor API health/logs.

The app is an implementation foundation, not a finished telecommunications service. Real number inventory, rentals, SMS delivery, admin workflows, support tickets, background job workers, and operational policies require a contracted provider and additional integration work.

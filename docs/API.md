# API overview

All application endpoints are rooted at `/api`. Health: `GET /health`. Authentication: `POST /auth/register`, `/auth/login`, `/auth/logout`, `/auth/forgot-password`, and `GET /auth/me`. Marketplace catalog: `GET /countries`, `GET /numbers`. Wallet: `GET /wallet`, `GET /wallet/transactions`, `POST /wallet/deposit`. Payment status: `GET /payments/status/:reference`. PayHero callbacks go directly to the Supabase Edge Function `https://rvmxonjgotrzdocdkpcj.supabase.co/functions/v1/payhero-webhook`.

Protected routes accept `Authorization: Bearer <Supabase access token>`. Unsupported number provisioning, SMS, and rental routes are intentionally absent until a provider adapter is implemented; the marketplace responds with an explicit disabled state.

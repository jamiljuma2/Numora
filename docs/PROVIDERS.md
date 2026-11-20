# Telecom providers

No carrier/number provider is enabled by default. This prevents the interface from implying live availability and avoids creating a real purchase path before supplier terms, country coverage, permitted use and webhook authentication are known.

Implement an adapter against the provider's official API, then synchronize availability into `provider_numbers`, provider country capabilities into `provider_countries`, and selling prices via `pricing_rules`. Provision first, commit the number purchase only after provider success, and use an idempotency key for retries. Keep supplier credentials in a secret manager and reference them from server-side configuration only.

Before launch, verify each provider's rules for temporary numbers, third-party service codes, message retention, voice support, geography, and account screening. Do not promise compatibility with any external service without evidence and permission.

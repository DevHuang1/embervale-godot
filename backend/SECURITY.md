# Embervale security controls

## Required production controls

- Configure an OIDC issuer, audience, and JWKS URL. Do not use the local JWT
  fallback in production.
- Use separate Render staging and production projects, databases, provider
  keys, webhook secrets, and allowed origins.
- Keep `DOCS_ENABLED=false` in production.
- Run Alembic migrations as a controlled release step before starting the web
  service. The service must not create tables in production.
- Configure provider webhooks with raw-body signing and a five-minute clock
  tolerance. Rotate secrets with an overlap window and revoke old credentials.
- Review `AuditLog` records and alert on repeated authentication, webhook, and
  mutation failures.

## Incident response

1. Disable checkout and provider fulfillment flags.
2. Revoke the affected session family or all refresh sessions.
3. Rotate OIDC, JWT, RevenueCat, Stripe, and database credentials as relevant.
4. Preserve audit and provider-event records for investigation.
5. Restore a database backup only into an isolated environment first.
6. Reconcile RevenueCat and Stripe state before re-enabling grants.

Tokens, provider secrets, and raw authorization headers must never be logged or
included in diagnostics.

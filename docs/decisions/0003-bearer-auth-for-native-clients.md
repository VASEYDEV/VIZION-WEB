# ADR-0003 — Bearer-token session transport for native clients

**Status:** accepted · 2026-09-03 · companion patch in `docs/companion/`

## Context

The web server reads the Supabase session from `@supabase/ssr` cookies. A native
app holds its session in the Keychain via `supabase-swift` and has no cookie jar
worth trusting. Reproducing the chunked cookie format is brittle and
undocumented; sending the raw JWT is the standard mobile pattern.

## Decision

- Middleware: an `/api/*` request carrying `Authorization: Bearer` skips the
  cookie gate and reaches the route.
- `createClient()`: with a bearer present, build a memory-only supabase-js
  client (`persistSession: false`) and `setSession({ access_token, refresh_token:
  "native" })`. For an unexpired token that call hits `/auth/v1/user`, so the
  token is **verified by Supabase Auth** before any route sees a user. An
  expired token cannot refresh (sentinel refresh token) and fails closed to 401.
  No cookies are written.
- Documents keep requiring cookies; a bearer on a page request is ignored.
- `DELETE /api/account` is added for App Store guideline 5.1.1(v), reusing the
  web form route's deletion logic (`purgeAccount`).

## Consequences

- The app must refresh tokens itself before calling — `supabase-swift` does.
- One small, reviewable server diff (8 files) validated by the web suite.
- Rate limiting stays per user id, unchanged.

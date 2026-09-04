# ADR-0002 — Keep the deployed web API as the model proxy

**Status:** accepted · 2026-09-03

## Context

The web repo's `/api/enhance` and `/api/media` route handlers hold twelve
providers' keys, the per-user rate limit, the atomic daily cost cap
(`spend_reserve`), the usage ledger, sixteen per-model formatters, the tolerant
envelope parser, the diff, and the SSE framing. All of it is tested and deployed.

## Options

1. Re-implement the adapter in the app (keys on device — a §6 violation).
2. Port the adapter to Supabase Edge Functions (Deno) — weeks of work and a
   second copy of policy that already drifts easily.
3. Call the existing routes with the Supabase JWT.

## Decision

Option 3. The app sends `Authorization: Bearer <access_token>`; the server
verifies it (ADR-0003). The app never learns a provider key, and every policy
change (prices, ladders, timeouts, salvage rules) lands once, server-side.

## Consequences

- The web deployment is a hard runtime dependency; previews work for testing.
- `VIZION_API_BASE_URL` is configuration, so staging/prod swaps are one line.
- Latency adds one hop through Vercel; acceptable for a streaming call that
  runs for seconds to minutes.

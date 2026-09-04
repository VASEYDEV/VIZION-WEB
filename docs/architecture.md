# VIZION for iOS — architecture

## Layers

```
┌─ iPhone ─────────────────────────────────────────────────────────────────┐
│ SwiftUI screens (Auth · Enhance · Library · Detail · Settings)           │
│   @Observable view models (transient run/attachment state)              │
│   AppEnvironment — composition root + gate (config → session → gate)    │
│   UIStore / EnhanceViewStore — UserDefaults, convenience only           │
│ Services                                                                │
│   SupabaseService  (supabase-swift: Auth/Keychain, PKCE)                │
│   LibraryRepository · ProfileRepository (PostgREST + Storage, user JWT) │
│   VizionAPI (URLSession · Bearer JWT · SSE)                             │
│ VizionCore (pure Swift: roster · contracts · diff · paging · media)     │
└──────────────┬───────────────────────────────┬───────────────────────────┘
               │ https                          │ https
               ▼                                ▼
   Vercel: vizion-io (Next 15 route handlers)   Supabase
     POST /api/enhance  → provider adapter        Postgres (RLS) · Auth · Storage
     POST /api/media    → vision adapter          RPCs: library_save_prompt,
     DELETE /api/account (companion)              library_add_version, media_reserve,
     rate limit · cost cap · usage ledger         media_commit, update_app_settings
```

The web app's server is the **model proxy**: keys, cost cap, spend reservations,
per-model formatters, and the diff all stay there ([ADR-0002](./decisions/0002-keep-the-vercel-api-as-model-proxy.md)).
Everything the browser did against Supabase directly (auth, library reads and
writes under RLS, storage) the app does directly too, through `supabase-swift`.

## Session and the gate

`AppEnvironment.gate` mirrors the web's middleware + `(app)/layout.tsx`:

```
configMissing → loading → signedOut → needsPassword → closed → app
```

- `signedOut`: no Keychain session → `AuthGateView` (magic link, password,
  Google/GitHub via `ASWebAuthenticationSession`, and Sign in with Apple
  through Supabase's id-token grant — ADR-0006, native-only).
- `needsPassword`: `profiles.auth_method = magic_link ∧ password_set = false`.
  Apple, like the other providers, is never gated — the provider is the credential.
- `closed`: `app_settings.open_access = false` and the user is not the recorded owner.
- Every `/api/*` request carries `Authorization: Bearer <access_token>`; the SDK
  refreshes before handing out a token, so the server never sees a stale one.

## Streaming

`VizionAPI.enhance` returns an `AsyncThrowingStream<EnhanceStreamEvent>` fed by
`URLSession.bytes(for:)` through `SSEParser` (VizionCore). The view model batches
`delta` events (~40 ms) and applies every event to `EnhanceStreamState`, whose
monotonic rules (snapshots raise, measurements replace, the char estimator stands
down after a measurement) are unit-tested. Cancellation propagates through task
cancellation → `EnhanceFailure.cancelled` (status 0, ignored by the UI).

## Persistence posture

- **Server is the source of truth.** `UIStore` (theme, mode, target, thinking
  levels, draft, media prefs, Auto, dial tip, format, lengths) and
  `EnhanceViewStore` (the last result + submitted snapshot + Polish decisions)
  live in UserDefaults and are scoped to the account; a switch wipes the previous
  user's draft/result.
- The web's IndexedDB **outbox** (offline saves replayed on `visibilitychange`)
  is not ported yet: a save that fails offline surfaces the error and keeps the
  result on screen. Tracked in `logs/parity-ledger.md`.

## Design system

`VZ` (Tokens.swift) is `tokens.css` as dynamic colours; `VZFont` the three type
roles; `GlassPanel` the `.glass`/`.glass-solid` tiers (Liquid Glass on iOS 26+);
`BrandMark` draws the master glyph via `SVGShape` from `BrandGlyph.pathData`
(pinned by a core test). Developer marks and the 24-grid icons are the web's own
SVG path strings through the same parser.

## Deep links

`vizion://enhance?draft=…` (Shortcuts/share sheet) · `vizion://library/<uuid>` ·
`vizion://auth/callback` (Supabase return). The `?draft=` rules — apply when the
editor is empty, offer (never overwrite) when it isn't, ignore over 8 000 chars —
are `DraftParam` in the core. Universal links on the web origin parse identically
and can be enabled with an `applinks:` entitlement + AASA file later.

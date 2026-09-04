# VIZION → SwiftUI migration plan

**Source:** `SeanVasey/vizion` @ `404e8ad` (2026-09-03) — Next.js 15 / React 19 PWA,
v0.3.0, all six web phases done.
**Target:** a native iOS app (SwiftUI, iOS 18+, Swift 6) in this repo, testable on an
iPhone on the current iOS developer beta, then TestFlight and the App Store.

## Strategy in three sentences

Keep the web deployment as the **model proxy and backend contract** — its route
handlers already hold the keys, the cost cap, the ledger, and the per-model
formatters, so the app never needs a provider SDK. Port the **domain** to a pure
Swift package that builds and tests anywhere, and rebuild the **UI** natively
against the web's own design tokens rather than wrapping the site. Where the web
solved an iOS-PWA limitation (share target, haptics, home-screen tile, storage
eviction), take the native capability instead.

## Phases and gates

| Phase | Deliverable | Acceptance | State |
| --- | --- | --- | --- |
| **M0 Foundation** | Audit, scaffold, XcodeGen, CI, docs, companion patch | `make core-test` runs; CI defined; patch applies to web `main` | ✅ |
| **M1 Core** | `VizionCore` with tests | Roster/modes/contracts/diff/paging/media/auth/deeplinks/svg ported; tests green on Linux | ✅ 52 tests |
| **M2 Design system** | Tokens, type, glass, buttons, marks, icons | Every token from `tokens.css` present for both themes; brand glyph pinned to the master | ✅ authored |
| **M3 Services** | Supabase, VizionAPI (SSE), repositories | Sign-in (4 methods), enhance stream, media analysis, library CRUD, profile | ✅ authored |
| **M4 Screens** | Auth · Enhance · Library · Detail · Settings | Every web surface has a native counterpart (see `screen-map.md`) | ✅ authored |
| **M5 Device** | Builds in Xcode; runs on the beta iPhone | First real enhance streams end-to-end; OAuth round-trips; library round-trips | ⬜ |
| **M6 Ship** | Icon Composer icon, privacy manifest, TestFlight, review notes | TestFlight build accepted; App Store submission | ⬜ |

## M5 — device bring-up checklist (next)

1. `make bootstrap`, fill `Config/Secrets.xcconfig`, `make open`.
2. Build. Expect and fix supabase-swift signature nits in `App/VIZION/Sources/Services/`
   (this is the one layer authored against a remembered API surface — see the
   local-dev runbook for the reconcile list).
3. Apply `docs/companion/0001-*.patch` to the web repo and deploy (preview is fine);
   point `VIZION_API_BASE_URL` at it.
4. Supabase → Auth → URL configuration: add `vizion://auth/callback`.
5. Run on the device: sign in with each method; enhance with a configured target;
   attach a photo; save; open in library; restore a version; change settings.
6. Record every divergence in `logs/development-log.md` and fix forward.

## M6 — ship checklist

- Icon Composer `.icon` from `Design/brand/vizion-icon-foreground-*.svg` (light/dark/clear/tinted).
- ~~`PrivacyInfo.xcprivacy`~~ ✅ authored (`App/VIZION/Resources/`).
- ~~Sign in with Apple (guideline 4.8)~~ ✅ ADR-0006; needs the App ID
  capability, the Supabase client id and the `APPLE_*` server env at bring-up.
- App Store metadata: name, subtitle, screenshots on a 6.9" device, privacy labels
  (email, user content), support URL, review notes with a test account.
- TestFlight internal → external; crash-free session on the beta OS.

## Out of scope (deliberately)

- Porting the provider adapters/formatters into the app or into Edge Functions.
- A macOS/Catalyst target.
- Realtime sync; the web's IndexedDB outbox becomes a simple retry — see the ledger.

## Risk register

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| supabase-swift API drift vs. what was authored | High | Low (localized) | `Services/` is the only consumer; reconcile once in Xcode |
| Web API rejects Bearer (patch not deployed) | Certain until deployed | Blocks all model calls | Patch validated; ship it first |
| iOS 26 SDK-only APIs on an older Xcode | Medium | Build break | `#if compiler(>=6.2)` + `#available` gates |
| App Review: account deletion, sign-in with Apple | Low | Rejection | `DELETE /api/account` in-app; Sign in with Apple shipped (ADR-0006), with Apple-token revocation on deletion (5.1.1(v)) |
| Fonts are latin subsets | Low | Tofu on non-latin input | Re-vendor full TTFs before ship |

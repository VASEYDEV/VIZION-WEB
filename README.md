<div align="center">

<img src="./App/VIZION/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" alt="VIZION" width="96" height="96" />

# VIZION for iOS

**The native SwiftUI successor to the VIZION web app — a VASEY/AI prompt-engineering studio.**

_Clarify · Polish · Expand · Condense · Reformat · Adapt — the same idea, fitted to the engine that's about to receive it._

</div>

> This repository migrates [`SeanVasey/vizion`](https://github.com/SeanVasey/vizion) —
> a Next.js 15 / React 19 progressive web app — to a native iOS app in Swift and
> SwiftUI, so it can be finished in Swift, tested on an iPhone running the
> current iOS developer beta, and submitted to the App Store. The web app stays
> deployed: its route handlers remain the model proxy this app talks to
> ([ADR-0002](./docs/decisions/0002-keep-the-vercel-api-as-model-proxy.md)).

## What's here

```
Packages/VizionCore/   Platform-agnostic Swift: the 16-model roster, the six modes,
                       thinking ladders, wire contracts (SSE + JSON), the word diff,
                       library paging/hashing, media formatters, deep links.
                       Builds + tests on Linux and macOS (`make core-test`).
App/VIZION/            The SwiftUI app: design system (tokens, type, glass, brand
                       mark, developer marks), Supabase auth + PostgREST + Storage,
                       the streaming enhance client, and every screen.
project.yml            XcodeGen spec → VIZION.xcodeproj (generated, gitignored).
Config/                Secrets.example.xcconfig → copy to Secrets.xcconfig (gitignored).
docs/                  MIGRATION-PLAN · architecture · screen-map · api-contract ·
                       decisions/ (ADRs) · runbooks/ · companion/ (web-repo patch).
logs/                  development-log.md (dated) · parity-ledger.md (feature parity).
tasks/lessons.md       Self-improvement loop — read before each phase.
Design/brand/          The master glyph + Icon Composer layers (reference, not rasterized).
```

## Status

| Phase | Scope | State |
| --- | --- | --- |
| **M0 Foundation** | Audit of the web app · repo scaffold · XcodeGen spec · CI · docs | 🟢 done |
| **M1 Core** | VizionCore: roster, modes, contracts, diff, paging, media, tests | 🟢 done (52 tests green on Linux) |
| **M2 Design system** | Tokens, fonts, glass, buttons, brand mark, developer marks, icons | 🟢 written — needs an Xcode build pass |
| **M3 Services** | Supabase auth (magic link · password · GitHub · Google), enhance SSE client, media, library, profile | 🟢 written — needs the companion web patch + Xcode pass |
| **M4 Screens** | Sign-in · Set password · Enhance · Library · Prompt detail · Settings | 🟢 written — needs an Xcode build + device pass |
| **M5 Device** | Build on the iOS developer beta, OAuth redirect, real-key runs | ⚪ next — [runbook](./docs/runbooks/device-testing.md) |
| **M6 Ship** | Icon Composer icon, privacy manifest, TestFlight, App Store | ⚪ [runbook](./docs/runbooks/release.md) |

Honest caveat: everything under `App/` was authored without an Apple toolchain in
the loop. `Packages/VizionCore` is compiled and tested; the app target is not
until it is opened in Xcode. Expect a first build to surface a handful of
signature mismatches against the resolved `supabase-swift` version — they are
localized to `Services/` by design ([local-dev runbook](./docs/runbooks/local-dev.md)).

## Getting started (macOS)

```bash
make bootstrap        # brew installs xcodegen/swiftlint/swiftformat/xcbeautify,
                      # copies Config/Secrets.example.xcconfig → Config/Secrets.xcconfig,
                      # generates VIZION.xcodeproj
# fill in Config/Secrets.xcconfig: SUPABASE_URL, SUPABASE_ANON_KEY, VIZION_TEAM_ID
make open             # regenerate + open in Xcode → run on your iPhone
```

Anywhere with a Swift toolchain (Linux included):

```bash
make core-test        # swift test --package-path Packages/VizionCore
```

## Before the first real run

1. **Apply the companion patch to the web repo.** The deployed API authenticates
   with Supabase cookies only; a native client sends a Bearer token. The patch in
   [`docs/companion/`](./docs/companion/README.md) adds bearer verification and the
   `DELETE /api/account` endpoint the App Store requires. It is validated against
   the web repo's own lint, typecheck, and unit suite.
2. **Allow the app's redirect URL in Supabase** (`vizion://auth/callback`) —
   [supabase-config runbook](./docs/runbooks/supabase-config.md).
3. **Run on the device** — [device-testing runbook](./docs/runbooks/device-testing.md).

## Architecture in one picture

```
iPhone (SwiftUI · iOS 18+, Liquid Glass on iOS 26+)
  ├─ VizionCore (pure Swift)  ·  UIStore / EnhanceViewStore (UserDefaults, convenience only)
  ├─ Supabase Swift ── Auth (Keychain session, PKCE) · PostgREST (RLS) · Storage
  └─ VizionAPI ── Authorization: Bearer <supabase jwt>
        │
        ▼
Vercel · vizion-io (Next route handlers = the model proxy; keys never leave it)
  ├─ POST /api/enhance   SSE stream: status · delta · usage · done · error
  ├─ POST /api/media     vision extraction (attributes / style / transcription)
  └─ DELETE /api/account (companion patch)
        │
        ▼
Supabase ── Postgres (RLS) · Auth · Storage (avatars, media)
```

Full map: [`docs/architecture.md`](./docs/architecture.md). Screen-by-screen
port: [`docs/screen-map.md`](./docs/screen-map.md). Wire contract:
[`docs/api-contract.md`](./docs/api-contract.md).

## Brand

VIZION is a **VASEY/AI** product. No association with VASEY.AUDIO. The identity
is the VIZION mark — a chevron framing a bar and split ring — drawn in-app from
the master path on the theme-aware accent ink (`Laser #C7FD26` on Void, deep
green on the light canvas). The app icon is the pinned dark tile (Void plate,
Laser glyph) the web's ADR-0015 settled on; an Icon Composer `.icon` for the
Liquid Glass appearances is an M6 item.

## License

[MIT](./LICENSE) © 2026 Sean Vasey (VASEY/AI). Vendored fonts under
`App/VIZION/Resources/Fonts/` are licensed separately under the
[SIL Open Font License 1.1](./App/VIZION/Resources/Fonts/OFL.txt).

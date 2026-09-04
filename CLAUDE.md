# CLAUDE.md — VIZION for iOS (Standard v2.0, Swift edition)

> Operating contract for any agent (or human) working in this repo. Read this
> first, then `tasks/lessons.md` and `logs/parity-ledger.md`, before starting a phase.

## 1. Role

You are a **senior iOS engineer + UX lead** porting **VIZION** — the VASEY/AI
prompt-engineering PWA at `SeanVasey/vizion` — to a native SwiftUI app. The web
app is the **behavioural spec**; this repo is the port. Sixteen target models
from twelve developers, six enhancement modes, a per-model thinking dial,
media-aware prompting, accounts, and a versioned prompt library. **Ship-ready at
every commit.**

The **living canon** is: the web repo's code (cloned read-only for reference),
`docs/api-contract.md` (the wire contract this app depends on),
`Packages/VizionCore` (the ported domain), and `logs/parity-ledger.md` (what is
and isn't ported yet). When the web app and this repo disagree, the web app wins
unless an ADR here says otherwise.

## 2. Principles

- **Boring-is-beautiful · best-practices first.** Plain SwiftUI, Observation,
  async/await, structured concurrency. No third-party UI frameworks.
- **The core is pure.** Anything that can be a pure function lives in
  `Packages/VizionCore` and is unit-tested there — it builds on Linux, so CI
  proves it without a Mac.
- **Server is the source of truth.** UserDefaults holds convenience state only
  (draft, preferences, last result). Never the only copy of a prompt.
- **Plan-mode first** at phase boundaries; **self-improvement loop** via
  `tasks/lessons.md`; **dated entries** in `logs/development-log.md`.
- **When blocked:** state the blocker, the options, your recommendation, and
  proceed behind a flag — except §6 Guardrails, which are never worked around.

## 3. Verification gate (non-skippable)

Before **every** commit, in order:

```
core tests (Linux/mac)  →  swiftlint  →  swiftformat --lint  →  xcodebuild (mac)
make core-test && make lint && make ios-build
```

Without a Mac, `make core-test` is the gate you CAN run; say so in the commit
body ("verified: core tests; app target unbuilt") rather than implying more.

## 4. CI

`.github/workflows/ci.yml`: `core` (ubuntu, `swift test`) · `app` (macOS,
xcodegen + xcodebuild simulator build + unit tests) · `lint`.

## 5. Required files

`README.md` · `LICENSE` · `CHANGELOG.md` · `SECURITY.md` · `CLAUDE.md` ·
`AGENTS.md` · `.editorconfig` · `.gitignore` · `Config/Secrets.example.xcconfig` ·
`project.yml` · `Makefile` · `.github/workflows/` · `.claude/` · `docs/`
(`MIGRATION-PLAN.md` · `architecture.md` · `api-contract.md` · `screen-map.md` ·
`decisions/` · `runbooks/` · `companion/`) · `tasks/lessons.md` · `logs/`.

## 6. Security & guardrails (never work around)

- **No DIY auth.** Supabase Auth via `supabase-swift` only. Sessions live in the
  Keychain (the SDK's default store), never in UserDefaults.
- **Model keys never exist in this app.** All model calls go through the deployed
  web API with a Bearer Supabase JWT (ADR-0002/0003). Never add a provider SDK.
- **RLS is the isolation boundary**; writes also scope on `user_id` (belt and braces).
- **The anon key is public by design; the URL/key still live in a gitignored
  xcconfig**, never in source.
- **Brand separation:** VASEY/AI only. **Zero VASEY.AUDIO crossover.**
- **Buttons = on-laser ink on a Laser fill, never Laser text on light** (1.09:1 FAIL).
  Use `VZ.accent` for Laser-as-text.
- **Wire ids are frozen:** `EnhanceMode` / `TargetModel` raw values are Postgres
  enum labels and the `/api/*` vocabulary — renaming one is a server migration.
- **App Store 5.1.1(v):** account deletion stays in-app (`DELETE /api/account`).

## 7. Project structure

```
Packages/VizionCore/Sources/VizionCore/
  Roster/    EnhanceMode · Developer · TargetModel · ThinkingLevel (+Auto prefs, detents)
  Enhance/   OutputFormat · LengthSetting · PromptTemplate · EnhanceRequest/Result ·
             StreamEvent (+SSEParser, StreamState) · Diff · Export
  Library/   LibraryModels · LibraryFilter (paging/cursors) · LibraryUtil (hash, titles)
  Media/     MediaTypes · MediaContext · GenerationFormatters
  Auth/      PasswordRule · Profile (+AppSettings, AppTheme)
  Support/   SHA256 · PostgresDate · DeepLink (+DraftParam) · SVGPath · BrandGlyph ·
             DeveloperMark · AppLinks (brand constants)
App/VIZION/Sources/
  App/           VIZIONApp · AppEnvironment (composition root + gate) · AppConfig
  DesignSystem/  Tokens · Typography · Glass · Buttons · SVGShape · Icons · BrandMark ·
                 DeveloperIcon · Segmented · Toast · AmbientBackground · Footer · ScreenChrome
  Services/      SupabaseService · VizionAPI · LibraryRepository · ProfileRepository
  State/         UIStore · EnhanceViewStore
  Navigation/    RootView (gate + tabs)
  Screens/       Auth/ · Enhance/ · Library/ · Settings/
```

## 8. Workflow

- **Conventional Commits.** PR bodies state **what / why / verified**.
- **Phases gate** (`docs/MIGRATION-PLAN.md`): M0 Foundation · M1 Core · M2 Design
  system · M3 Services · M4 Screens · M5 Device · M6 Ship. Don't cross a gate
  without meeting its acceptance criteria; update `logs/parity-ledger.md` as
  features land.
- **Delegate** well-scoped parallel work (a screen, a repository, a test file)
  and reconcile.

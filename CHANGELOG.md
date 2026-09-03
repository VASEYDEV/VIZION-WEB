# Changelog

All notable changes to VIZION for iOS are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — M0 Foundation · M1 Core · M2 Design system · M3 Services · M4 Screens (2026-09-03)

- **Repository scaffold**: XcodeGen spec (`project.yml`), gitignored generated
  project, `Config/Secrets.example.xcconfig`, Makefile, bootstrap script,
  swiftlint/swiftformat config, GitHub Actions (Linux core tests · macOS
  simulator build · lint), Claude settings.
- **`Packages/VizionCore`** — the platform-agnostic port of the web app's domain:
  the sixteen-model roster with developer grouping and legacy-id migration; the
  six modes with labels/blurbs; thinking ladders per target + Auto preferences
  and dial detents; output formats and per-mode length labels; prompt templates;
  the `/api/enhance` request/result contracts and an incremental SSE parser with
  the monotonic stream-state rules; the word-level LCS diff with hunks,
  per-change decisions, and section counts; Markdown/JSON/text exports; library
  card/facet/draft/version models, filter + keyset cursor plumbing (quoted,
  UUID-pinned), relative time, title derivation, tag parsing, and the
  sha256 content hash (dependency-free SHA-256); media kinds/roles/intents,
  reference-context builders, generation-syntax formatters, and the storage
  budget; the password rule and onboarding gate; a Postgres timestamp parser;
  deep-link + `?draft=` intake rules; an SVG path parser (arcs → cubics) with
  the master brand glyph and the twelve developer marks. **52 unit tests, green
  on Linux (Swift 6.3.3).**
- **Design system**: the seven locked roles as dynamic colours (light/dark),
  the three type roles from the vendored OFL fonts (converted WOFF2 → TTF),
  glass panels (Liquid Glass on iOS 26+, material fallback), Laser/secondary/
  pressable button styles, the brand mark + wordmark + pills + footer, developer
  icons, the stroked 24-grid icon set, a segmented control, toasts, the ambient
  ground.
- **Services**: Supabase auth (magic link, email+password, GitHub/Google via
  `ASWebAuthenticationSession` + PKCE), the streaming enhance client, the media
  analysis client, account deletion, library/drafts/collections/activity over
  PostgREST, profile/avatar/app-settings/media/export over PostgREST + Storage.
- **Screens**: auth gate + set-password; the composer (mode rig, editor,
  templates, attachments with roles and privacy notice, target picker with Auto
  + budget, thinking dial, shape/depth rails, streaming progress, result view
  with copy/use/save/share/export, Polish per-change review, Clarify questions,
  refine chips, cap banner, `?draft=` offer); library (search, filter sheet,
  quick chips, cards with swipe/context actions, load more, collections, drafts
  with resume/edit, activity feed, new-prompt save-or-discard); prompt detail
  (rename, tags, history + restore, compare any two, revise → new version);
  settings (identity + avatar, email/password/sign-out, default model with Auto
  clear, theme + reduced effects, stored media + export + delete account, owner
  console, about).
- **Companion patch for the web repo** (`docs/companion/`): Bearer-token session
  verification for `/api/*` and `DELETE /api/account`, validated against the
  web repo's typecheck, lint, Prettier, and unit suite.
- **Docs**: migration plan, architecture, screen map, API contract, five ADRs,
  runbooks (local dev, device testing, Supabase config, release), lessons,
  development log, parity ledger.

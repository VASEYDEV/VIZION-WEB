# Development log

Dated, append-only. One entry per working session; link the commit.

## 2026-09-03 — Session 1: audit, scaffold, core, design system, services, screens

**Environment:** Linux (Ubuntu 24.04) agent session; Swift 6.3.3 toolchain from
swift.org installed to `/opt/swift`; Node 22 for validating the companion patch
against a shallow clone of `SeanVasey/vizion` @ `404e8ad`.

**Audit.** Read the web repo end to end: architecture, tokens, constants, modes,
lengths, formats, templates, stream events, the enhance and media routes,
`database.types.ts`, the UI and view stores, library queries/actions/paging,
drafts, profile/auth/owner actions, media types/context/formatters/pipeline,
the composer/result/library/settings components, brand mark, developer icons,
fonts, lessons, ADRs. Wrote `docs/api-contract.md` and `docs/screen-map.md` from it.

**Finding (blocking):** `/api/*` authenticates with Supabase cookies only. Wrote
the companion patch (bearer verification + `DELETE /api/account`), validated
with the web repo's typecheck, eslint, prettier, and Vitest (77 tests in the
touched files), and `git apply --check` on a clean `origin/main` worktree.

**Built.** `Packages/VizionCore` (25 source files, 5 test files, 52 tests green
on Linux, Swift 6 language mode). App target: 13 design-system files, 4
services, 2 stores, composition root, 3 navigation/auth files, 5 enhance files,
3 library files, 1 settings file, 2 test files. Fonts converted WOFF2 → TTF.
Opaque 1024 icon + tinted variant rendered from the master glyph.

**Not done / next (M5):** open in Xcode on a Mac, reconcile supabase-swift
signatures, deploy the companion patch, allow the redirect URL, run on the beta
iPhone. Parity gaps are itemised in `logs/parity-ledger.md`.

**Verified:** `swift build` + `swift test` for VizionCore. NOT verified: any
`App/` compilation.

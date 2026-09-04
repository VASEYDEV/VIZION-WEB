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

## 2026-09-04 — Session 2: CI reconcile on PR #1 + review fixes

**CI on `5259000`.** `VizionCore · swift test (Linux)` green. `VIZION · xcodebuild`
failed on exactly one error — `IconView(.paperclip…)` built inside the
`PhotosPicker` label closure hit a main-actor-isolated initializer from a
nonisolated context (SE-0434: an *explicit* init on a `View` struct is isolated;
the implicit memberwise one is not). `swiftlint · swiftformat --lint` failed with
325 violations, most of them `identifier_name` on snake_case Codable rows,
`line_length` on SVG path data and user copy, and structural limits.

**Tooling.** Fetched the Linux binaries so the gate is runnable here: SwiftFormat
0.63.0 and SwiftLint 0.65.1 (`swiftlint_linux_amd64.zip`). `make lint` now
means something on this box; the first blind fix attempt (file-top
`// swiftlint:disable` lines with prose after the rule name) would itself have
produced ~100 `blanket_disable_command`/`superfluous_disable_command` errors.

**Fixes.** `nonisolated init` on `IconView` and `ScreenHeader`. Lint: config
tightened to what the code actually needs (`identifier_name` min 1 + `_` allowed
for wire-shaped rows, `large_tuple` off for the cursor/geometry tuples,
line length 110/140 with multi-line copy literals ignored, nesting 3); SVG path
data sits inside tight `disable`/`enable` regions; user-facing copy became
multi-line literals; `LibraryRepository` split (`+Drafts.swift`), the
library sheets moved to `LibrarySheets.swift`, the composer view model's
attachment pipeline moved to a same-file extension with a `flush(_:applying:)`
helper replacing four copies of the batch-apply dance; `settingWrite` takes a
labelled `work:` closure.

**Review (Codex, 7 findings — all verified real, all fixed).** Run button gated
on `attachmentsPending`; storage bytes/MIME/extension now agree (`prepare`
keeps PNG/JPEG/WebP/GIF verbatim, transcodes the rest to JPEG); stale library
reloads discarded by generation; bare `vizion://library` and `vizion://settings`
now route; links pending at tab-view entry honoured (`initial: true`); draft
resume switches tabs via `pendingTab`; a role change mid-analysis re-queues
instead of marking ready with the wrong intent.

**Verified:** `swift test` (52 green) · `swiftformat --lint` clean ·
`swiftlint --strict` clean (0.65.1) · `swiftc -parse` on every `App/` source.
NOT verified: `xcodebuild` — the app target still compiles only in CI.

**Later the same session — first green app build.** After three more CI
rounds (`ScreenHeader` init isolation, `client` access for the Drafts
extension, SwiftFormat/SwiftLint version drift on the runner) `xcodebuild`
reported **Build Succeeded** for the app target on `14c2e88` — the first
time the `App/` sources have compiled under an Apple toolchain. The unit-test
step then failed before running: the simulator-name grep captured a trailing
space (`iPhone 16 Pro `), which the destination matcher rejects. Fixed in the
workflow; the app unit tests (UIStore, AppConfig) are the next unknown.

**Review rounds (same session, 02:25–03:00 UTC).** Codex reviewed every push
and raised 31 findings across five rounds; each was checked against the web
sources before anything changed. 28 were real defects in the port and are
fixed (media lifecycle and quota, owner-console toggle hydration, run and
revision generations, stale load-more pages, draft-editor and version-body
failure states, the tray cap, the signup gate while settings load, the
Describe wire intent, serialized settings writes, success toasts gated on
the write). Three were declined or narrowed because the web deliberately
behaves that way — refinement saves keep the original submitted input,
Reference and Describe share one analysis family, Clear never touches the
tray — and the threads say so with the web reference. Every thread is
resolved. First fully green CI (core · xcodebuild + app unit tests · lint):
`5e5d95d`; green again on the review heads through `db8b6e4`.

**PR #1 merged** (`bab272b`, 05:08 UTC, merge commit). Codex's last round on
`a36e188` (three findings: the OAuth session object was not retained for the
flow — P1; a nil-diff refinement mislabelled the original as "Previous
result"; the Supabase package was a `from:` range with no checked-in
resolution) landed after the merge, so the branch was restarted from `main`
and the fixes go up as a follow-up PR.


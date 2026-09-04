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

## 2026-09-04 — Session 3: PR #2 green, then M6 prep (Apple sign-in + privacy manifest)

**PR #2** (`101966c`, the three findings Codex raised on `a36e188` after PR #1
merged) came back green on all three jobs — core tests, the macOS
`xcodebuild` build + unit tests, and lint — with no review threads. Nothing
was left to drive there, so the session moved to M6 preparation: the two ship
items that need no Mac.

**Privacy manifest.** `App/VIZION/Resources/PrivacyInfo.xcprivacy`. The
required-reason APIs were found by scanning the app AND the pinned dependency,
not from memory: `UserDefaults` (`CA92.1`) in `UIStore`/`EnhanceViewStore`, and
file timestamps (`C617.1`) reachable through supabase-swift's multipart
uploader. Six collected data types, all linked, none for tracking; the release
runbook now lists the same set next to the App Store Connect labels so they
cannot drift apart. Validated by parsing it with `plistlib` and `xmllint`.

**Sign in with Apple (ADR-0006).** Guideline 4.8 wants a privacy-preserving
option beside Google and GitHub, so this is the first deliberate divergence
from the web — the ADR says so explicitly. The native flow was chosen over
Supabase's web OAuth: `SignInWithAppleButton` mints the credential and
`auth.signInWithIdToken` verifies it, with no browser round trip and no
`vizion://` return. Every signature was read out of supabase-swift 2.55.1's
own sources (the pinned tag) before it was used. `SignInNonce` lives in
VizionCore — 32 random bytes, SHA-256 to Apple, raw to Supabase — so the
replay protection is pure and testable on Linux.

Three details the guideline forces and the web never had to solve:

- Apple sends the user's name **once**, to the app only, so `handle_new_user()`
  has nothing to copy. `seedFullName` writes it, and never over an existing name.
- The id-token grant has no `shouldCreateUser`, so closed registration reuses
  the OAuth rule: stamp the attempt, purge an account created after it.
- Offering Apple obliges the app to **revoke** Apple's tokens on deletion
  (5.1.1(v)). That needs a refresh token, which only Apple's single-use
  authorization code buys — hence `POST /api/auth/apple` in companion patch
  0002 and the revoke at the top of `purgeAccount`, before anything is
  destroyed, so a failed revoke leaves a retryable state.

**Companion patch 0002.** Two migrations (the `apple` enum label in its own
migration — a new enum value cannot be used in the transaction that adds it —
then the trigger and the `apple_refresh_tokens` table with own-row RLS), the
Apple ES256 client-secret helper, the route, the revoke in `purgeAccount`, the
generated types, the settings label, a SECURITY.md bullet, and 22 new test
cases. Verified in a worktree of the web `main` with 0001 applied:
`npm run lint` ✓ · `tsc --noEmit` ✓ · `prettier --check` ✓ · `vitest run`
(111 files, **1500 tests**) ✓, then `git apply --check` of 0001 then 0002 onto
a clean `404e8ad` ✓.

**Verified here:** `swift test` (55 green, +3 auth cases) · `swiftformat --lint`
clean · `swiftlint --strict` clean · `swiftc -parse` on every edited app file.
NOT verified: `xcodebuild` — no Apple toolchain on this box, so the app target
and the new `AuthenticationServices` code compile only in CI, and Sign in with
Apple itself cannot be exercised until the device pass.


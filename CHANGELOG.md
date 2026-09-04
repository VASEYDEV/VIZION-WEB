# Changelog

All notable changes to VIZION for iOS are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — M6 prep: Sign in with Apple + privacy manifest (2026-09-04)

- **Sign in with Apple** (ADR-0006), the App Store 4.8 counterpart to the
  Google and GitHub buttons and the first place this app deliberately does
  more than the web. Native flow: `SignInWithAppleButton` mints the
  credential, Supabase's id-token grant verifies it. `SignInNonce` (VizionCore,
  32 random bytes; SHA-256 to Apple, raw to Supabase) makes a token
  unreplayable. The name Apple sends once seeds `profiles.full_name` and never
  overwrites a name already there. Closed registration works exactly as for
  OAuth — an account minted after the stamped attempt is removed again.
- **`PrivacyInfo.xcprivacy`**: required-reason APIs (UserDefaults `CA92.1`,
  file timestamp `C617.1`), no tracking, and the six collected data types,
  matching the App Store Connect labels in the release runbook.
- **Companion patch `0002-sign-in-with-apple.patch`** for the web repo: the
  `apple` enum label and `handle_new_user()` mapping, `POST /api/auth/apple`
  (exchanges Apple's authorization code for a refresh token), and
  `purgeAccount` revoking that token before it deletes anything — Apple
  requires revocation on account deletion (guideline 5.1.1(v)).

### Fixed — CI reconcile + review round (2026-09-04)

- **Build**: `IconView` and `ScreenHeader` initializers are `nonisolated` so a
  view can be built inside a nonisolated builder closure (SE-0434).
- **Composer**: the run button waits for attachments that are still
  reserving/uploading/analyzing; a role change while an analysis is in flight
  re-queues the file instead of accepting the stale result; storage bytes,
  MIME and file extension always agree (PNG/JPEG/WebP/GIF kept verbatim, other
  formats transcoded to JPEG).
- **Library**: stale reloads no longer overwrite a newer filter's results;
  resuming a draft switches to the composer.
- **Deep links**: bare `vizion://library` and `vizion://settings` route to their
  tabs, and links pending when the tab view appears are honoured.
- **Media**: removing a kept attachment from the tray deletes its stored file
  and record (web parity); an item removed mid-upload leaves nothing behind;
  deletion removes the Storage object first and the record only after Storage
  confirms, so a failed delete stays visible and retryable.
- **Owner console**: the open-access toggle writes only on a user edit, never
  on hydration or rollback; the developer accent strength now drives the
  library-card corner field (+2 in light mode, as the web).
- **Library**: a load-more page that lands after a filter change is
  discarded; archive and delete toasts show only after the write succeeds.
- **Makefile**: `ios-build`/`ios-test` propagate xcodebuild failures
  (`pipefail`, no unconditional success).
- **Composer runs**: a cancelled run can no longer finish after its replacement
  started and hide the new stream (run generations, also for prompt-detail
  revisions, where a stream ending without `done` now reports an error
  instead of spinning forever).
- **Attachments**: the analysis copy stays until removal so a role change made
  after Ready re-analyzes instead of marking the new role ready with nothing.
- **Library**: the Recent chip is the web's default view (clears every filter)
  rather than a sort toggle that silently dropped some; resuming a draft
  follows the web — the composer takes the draft and a failed server delete is
  announced instead of leaving the editor and the list disagreeing; the
  "Restored" toast waits for the write to succeed.
- **Attachments**: the tray caps at four across picker sessions (the number of
  reference blocks a prompt carries), the picker offers only the remaining
  room, and Clear leaves the tray alone as the web does, so it can never
  orphan a kept asset.
- **Library**: All/Favorites/Drafts chips carry the whole filter (tag and
  collection included); a version body that fails to load shows the error
  with Retry instead of an endless spinner.
- **Privacy**: the photo-library purpose string states that an attached photo
  is sent to the selected model for analysis and stored only if kept.
- **Sign-in**: magic-link signup stays closed until the open-access setting
  has actually loaded (fail-open afterwards, as the web).
- **Attachments**: the Describe role sends the `describe` intent (web
  `ROLE_INTENT`); it still shares the reference analysis family.
- **Library**: a draft body that fails to load shows the error with Retry
  instead of an empty editor; the Drafts view hides the sort control and
  keeps the default order its query actually uses.
- **Settings**: writes from one control run in order and only the latest may
  report or roll back.
- **Settings**: a failed stored-media refresh keeps the last-known rows and
  shows the error with Retry instead of reading as "0 B stored".
- **Collections**: rename is reachable (swipe → Rename → name prompt), as the
  web's per-row rename.
- **Companion patch**: account deletion stops if the avatar removal reports
  an error, so a public avatar can never outlive its owner's credentials.
- **Sign-in**: the in-flight `ASWebAuthenticationSession` is retained for the
  whole OAuth flow, so it can no longer be released mid-flow and leave the
  form stuck in its busy state.
- **Result**: a refinement whose diff exceeds the budget shows the result it
  was seeded from under "Previous result", not the author's original.
- **Build**: `supabase-swift` is pinned to an exact version in `project.yml`
  (the generated `Package.resolved` is gitignored, so the pin is the
  reviewable resolution).
- **Sign-in (security)**: an account that a Google/GitHub sign-in mints while
  registration is closed is removed again through the companion endpoint and
  signed out — OAuth cannot be told `shouldCreateUser`; the runbook names the
  project-level switch for hard enforcement. The proof that the sign-in
  minted the account is the app's own OAuth attempt stamp: only an auth user
  created after that instant qualifies, never an account that is merely young.
- **Owner console**: saving the accent strength refreshes the app settings so
  library cards render the new value at once, and a failed save rolls the
  slider back to the stored value.
- **Accounts**: an account counts as hydrated only once its profile was
  actually read, so a refresh that fails at launch is retried by the next one.
- **Drafts view**: entering it clears tag and collection as well as sort, since
  the drafts query applies none of them.
- **Result**: a Polish review decision clears the "Saved" state, since the
  shown output is no longer the saved one.
- **Accounts**: the last result is re-scoped to the signed-in user before any
  network call, so another account's cached enhancement can never show even
  when the profile request fails; composer defaults hydrate once per account
  (web `ProfileHydrator`), not on every refresh.
- **Lint**: SwiftLint config matched to the wire-shaped Codable rows and the
  cursor tuples; SVG path data in tight disable regions; long user copy as
  multi-line literals; `LibraryRepository`, `LibraryScreen` and the composer
  view model split into extensions/files under the structural limits.

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

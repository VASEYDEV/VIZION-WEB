# AGENTS.md — VIZION for iOS

The authoritative operating contract lives in `CLAUDE.md`. Read it first, then
`tasks/lessons.md`. This file adds only environment and runtime notes.

## Shape of the thing

One iOS app (SwiftUI, iOS 18+, Swift 6 language mode) built from a local Swift
package (`Packages/VizionCore`) plus one remote dependency (`supabase-swift`
2.x), talking to the deployed VIZION web API and to Supabase directly.

## Commands

- `make bootstrap` — first run on a Mac (Homebrew tools, secrets template, xcodegen).
- `make generate` / `make open` — regenerate `VIZION.xcodeproj` from `project.yml`.
- `make core-test` — the platform-agnostic gate; works on Linux with a Swift 6 toolchain.
- `make lint` — swiftlint + swiftformat --lint.
- `make ios-build` / `make ios-test` — simulator build/tests without signing.

## Non-obvious gotchas

- **The `.xcodeproj` is generated and gitignored.** Edit `project.yml`, never the
  pbxproj. A missing project means you haven't run `make generate`.
- **`Config/Secrets.xcconfig` must exist for XcodeGen** (it is referenced from
  `project.yml`). `make bootstrap` copies the example. URLs in xcconfig need the
  `https:/$()/host` spelling — `//` starts a comment.
- **Nothing model-shaped runs without the deployed web API.** `VIZION_API_BASE_URL`
  points at the Vercel deployment (a preview URL works). That deployment must
  carry `docs/companion/` — without it every `/api/*` call is a 401.
- **`App/` has not been compiled by an Apple toolchain yet** (M0–M4 were authored
  on Linux). `Packages/VizionCore` has. Expect the first Xcode build to raise
  supabase-swift signature nits in `Services/`; fix there, not by wrapping.
- **Linux core tests need Swift ≥ 6.0.** `swift-actions/setup-swift@v2` in CI;
  locally a swift.org toolchain tarball works (see `logs/development-log.md`).
- **iOS 26 Liquid Glass calls are gated** with `#if compiler(>=6.2)` +
  `#available(iOS 26, *)` so the tree also builds on Xcode 16. Keep both gates.
- **Fonts are registered by PostScript name** (`RedditSans-Medium`, not
  "Reddit Sans"); the vendored TTFs are latin subsets converted from the web's
  WOFF2. Re-vendor full TTFs before shipping non-latin UI.
- **The Photos picker transcodes HEIC to JPEG on the way in** (`ImageProcessing`)
  so the `media` bucket's MIME allowlist accepts it.

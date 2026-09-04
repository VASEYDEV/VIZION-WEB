# Lessons — self-improvement loop

> Append after each phase: **what broke · what changed · what to avoid next time.**
> Read this file before starting the next phase.

## 2026-09-03 — M0–M4 authored on Linux (no Apple toolchain)

- **Split the port at the "can it compile here" line.** Everything pure went into
  `VizionCore` and is *proven* (52 tests on a swift.org Linux toolchain); the app
  target is *written*. Say which is which in every status line — "green" for the
  core does not mean the app builds.
- **Read the wire contract before the UI.** The route handlers, `stream-events.ts`
  and `database.types.ts` were worth more than any component: the app is a client
  of that contract, and the contract is what could not be re-invented.
- **The blocker was authentication, not rendering.** The web API reads cookies
  only; a native client cannot honestly produce them. A companion server patch
  (validated against the web repo's own suite) was the smallest fix — decide the
  transport before writing a single network call.
- **Tuples with labels don't unify with tuples without.** `isRelative ? current :
  (0.0, 0.0)` fails against `(x:, y:)`; annotate the binding. Cheap to find with a
  compiler, expensive without one — which is the argument for the core package.
- **`swift-tools-version 5.10` cannot name `.iOS(.v18)`.** Use 6.0 and set
  `swiftLanguageModes` explicitly.
- **Working directory drifts between tool calls.** Three files silently landed in
  the wrong place; always write with absolute paths in automation.
- **The web's icon PNGs are transparent by design** (PWA `any` matrix). An App
  Store icon must be opaque — compose it from the master glyph, don't copy a PNG.
- **WOFF2 is not a font iOS registers.** Convert to TTF (fontTools + brotli) and
  register by PostScript name; the Reddit Sans weights ship as separate families.
- **Keep the design tokens as code, sourced from the locked CSS**, with the exact
  light/dark pairs. The contrast law (on-laser ink on Laser; `accent` for Laser-
  as-text) is the rule most likely to be broken by a "quick" colour change.

## 2026-09-04 — First CI round (PR #1)

- **Fetch the real linters before "fixing" lint blind.** The Linux SwiftLint
  asset is `swiftlint_linux_amd64.zip` (not `swiftlint_linux.zip`); one wrong
  URL cost a full CI round of guessed rule behaviour. Guessing was wrong twice.
- **SwiftLint's disable-command rules are on by default.** A file-top
  `// swiftlint:disable x` with no matching `enable` is `blanket_disable_command`;
  every word after the rule name parses as another rule id and fires
  `superfluous_disable_command`. Use tight `disable`/`enable` regions or
  `:next`/`:this`, and never put prose on the command line.
- **`:next` can't cross a doc comment.** A `// swiftlint:disable:next` between a
  `///` block and its declaration orphans the doc (`orphaned_doc_comment`) and
  misses the target; put `// swiftlint:disable:this` on the declaration line.
- **SE-0434 bites view inits.** An explicit `init` on a `View` struct is
  main-actor-isolated; the implicit memberwise one is not. Any view constructed
  inside a nonisolated builder closure (`PhotosPicker` label) needs
  `nonisolated init` — the same shape SwiftUI's own containers use.
- **Format first, then lint.** SwiftFormat rewraps at 100 columns and SwiftLint
  measures at 110; hand-counting columns before formatting is wasted work, and
  `let`-hoisting a `String(format:)` beats a `specifier:` interpolation that
  cannot be split.
- **Two closures → label the second.** `multiple_closures_with_trailing_closure`
  is default-on; a helper that takes `rollback:` and work needs `work:` too.
- **Split by extension, not by config.** `type_body_length` counts the type
  body only, so moving a coherent section (the attachment pipeline) into a
  same-file extension keeps `private` access and drops the count honestly;
  raising the limit would have hidden it.
- **`nonisolated init` needs Sendable stored properties.** Under SE-0434 only
  Sendable stored properties of a main-actor `View` are nonisolated; a struct
  holding a generic child view (`action: Action`) cannot assign it from a
  nonisolated init. Reserve `nonisolated init` for leaf views built inside
  nonisolated builder closures (`IconView`), never for containers.
- **Splitting a type across files changes access.** A same-file extension sees
  `private`; a `+Drafts.swift` extension does not. When moving members out,
  grep the moved code for every `private` it touches (`client` was missed) and
  lift those to internal in the same commit.

## 2026-09-04 — Review rounds on PR #1

- **Check every bot finding against the web before changing anything.** 28 of
  31 were real; the 3 that were not all pointed at behaviour the web chose on
  purpose (refinement provenance, the describe/reference family, Clear leaving
  the tray). "The web wins" (CLAUDE.md §1) decided those in minutes — and the
  reply on the thread cites the file so the next reviewer does not re-raise it.
- **Every fire-and-forget Task needs an owner generation.** Runs, revisions and
  settings writes all had the same bug shape: a cancelled or slower predecessor
  finishing after its replacement and writing stale state. One counter bumped
  on start/cancel, checked after every await, fixes the class; a helper such as
  `finish(generation:failure:)` keeps the guard out of the hot loop.
- **A `try?` in a load path is a spinner that never ends.** Version bodies,
  draft bodies and the settings row each hid a failure behind `nil`; record the
  error and show a Retry instead.
- **Ordering rules must be the web's, not the reviewer's.** Object-then-row on
  delete, composer-then-server on draft resume, fail-open on the settings row:
  each came straight from `pipeline.ts` / `DraftsList.tsx` / `settings.ts`.


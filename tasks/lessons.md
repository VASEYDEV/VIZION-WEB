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

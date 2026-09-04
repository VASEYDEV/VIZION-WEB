# ADR-0001 — A native SwiftUI rewrite, not a wrapped web view

**Status:** accepted · 2026-09-03

## Context

VIZION ships as an installable PWA. Its web repo documents, in detail, the iOS
limits it works around: no share target, no haptics, a home-screen tile iOS
freezes at capture, storage eviction, 16px focus-zoom rules, and a WebKit e2e
project that cannot prove iOS behaviour. The owner wants to finish the product
in Swift, test on the current iOS developer beta, and submit to the App Store.

## Options

1. **WKWebView shell** around the deployed site — fastest, but inherits every
   limitation above, is a thin wrapper App Review dislikes, and gives no native
   surface to finish the product in.
2. **Cross-platform framework** — a second toolchain for one platform.
3. **Native SwiftUI**, keeping the web app's server as the backend and porting
   the domain to a pure Swift package.

## Decision

Option 3. The web app remains the behavioural spec and its server the model
proxy; the domain (roster, modes, contracts, diff, paging, media rules) becomes
`VizionCore`, unit-tested on Linux so CI never needs a Mac for the logic; the UI
is rebuilt on the same tokens with native affordances (share sheet, haptics,
Photos, Keychain, Liquid Glass).

## Consequences

- Two codebases share one wire contract (`docs/api-contract.md`); breaking
  changes to `/api/*` must be coordinated.
- Design fidelity is by construction (tokens as code, the master glyph path),
  not by wrapping.
- The first Xcode build is a real milestone (M5); the Linux-authored app target
  will need a reconcile pass.

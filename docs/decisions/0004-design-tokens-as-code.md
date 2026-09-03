# ADR-0004 — Design tokens and marks as code, from the web's sources

**Status:** accepted · 2026-09-03

## Context

`tokens.css` is LOCKED in the web repo with a contrast law (on-laser ink on a
Laser fill; Laser never as text on light) and theme-swapped roles. The brand
mark, the developer marks, and the icons are single SVG paths. An asset-catalog
translation by hand would drift.

## Decision

- Colours: `VZ` static dynamic colours with the exact hex/alpha pairs for dark
  and light; no asset catalog colours except `AccentColor`.
- Type: the vendored OFL WOFF2 files converted losslessly to TTF and registered
  by PostScript name.
- Geometry: a small SVG path parser in the core (`SVGPathParser`, arcs → cubics,
  unit-tested) renders the master glyph (`BrandGlyph.pathData`, pinned to the
  file by a test), the twelve developer marks (generated from
  `DeveloperIcon.tsx`), the provider marks, the footer monograms, and the
  24-grid icons from the web's own `d` strings.
- Icon: an opaque 1024 PNG composed from the master glyph with the Icon
  Composer padding (Void plate, Laser glyph — the web's ADR-0015 tile), plus a
  tinted variant. The Liquid Glass `.icon` is an M6 task.

## Consequences

- A brand retune is a hex edit in one file; a re-cut glyph fails a core test.
- Icons are stroked at draw time, so they scale with Dynamic Type sizes.

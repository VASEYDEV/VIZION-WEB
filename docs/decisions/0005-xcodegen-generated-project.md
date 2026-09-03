# ADR-0005 — XcodeGen spec instead of a committed .xcodeproj

**Status:** accepted · 2026-09-03

## Context

This repo is authored and reviewed largely by agents without a Mac in the loop.
A committed `project.pbxproj` is unreviewable and merge-hostile.

## Decision

`project.yml` is the source of truth; `VIZION.xcodeproj` is generated
(`make generate`) and gitignored. Configuration comes from a gitignored
`Config/Secrets.xcconfig` (template committed). CI generates the project on
macOS before building.

## Consequences

- One `brew install xcodegen` on a new Mac (`make bootstrap` does it).
- Targets, Info.plist keys, entitlements, and package deps are diffable text.
- If a future need (Icon Composer assets, extensions) outgrows XcodeGen, the
  generated project can be committed then — the reverse is not true.

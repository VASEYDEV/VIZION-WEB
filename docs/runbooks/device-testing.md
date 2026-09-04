# Runbook — testing on an iPhone running the iOS developer beta

## Prerequisites

- The **Xcode beta** matching the installed iOS beta (Apple Developer → Downloads).
  A release Xcode cannot target a newer beta OS.
- Your Apple Developer team id in `Config/Secrets.xcconfig` (`VIZION_TEAM_ID`).
- Developer Mode enabled on the iPhone (Settings → Privacy & Security → Developer Mode).
- Sign in with Apple configured (App ID capability + Supabase client id) — see
  `supabase-config.md`. It is the one method the simulator cannot exercise
  against a real Apple ID.
- The companion patch deployed to the web app (a Vercel preview is enough) and
  `VIZION_API_BASE_URL` pointing at it.
- `vizion://auth/callback` allowed in Supabase (see `supabase-config.md`).

## Loop

1. `make open` → pick the iPhone → Run (⌘R). First run: trust the developer
   certificate on the phone (Settings → General → VPN & Device Management).
2. **Sign in.** Try magic link (open the mail on the phone — the link returns
   to the app via `vizion://auth/callback`), then Google and GitHub (system
   web-auth sheet), then password, then **Apple** (the system sheet, no browser
   round trip). On a first Apple authorisation check that Settings → Identity
   shows the name Apple sent and Connection reads "Connected with Apple"; then
   sign out and back in with Apple to confirm the second run mints nothing new.
   To re-test the first-run path, revoke the app under Settings → your name →
   Sign in with Apple.
3. **Enhance.** Pick a target whose key is configured on the server; run a
   Clarify. Watch the ticker climb and the result land. Try a refine chip, a
   Polish with per-change revert, a Reformat with a shape, Auto with each budget.
4. **Attach.** Add a photo as Reference; confirm the description arrives and the
   context rides the next run (the result's rationale should mention it).
5. **Save** → open in Library → rename, tag, favorite, move to a collection,
   restore a version, compare two, revise → save as version. Swipe to favorite.
6. **Settings.** Change theme (both themes render every screen), default model
   (including clearing to Auto), avatar, email, password. Export data. Sign out.
7. **Shortcuts.** In Shortcuts, "Open URL" `vizion://enhance?draft=[URL Encoded Text]`
   with "Show in Share Sheet" — with an empty composer it fills; with a draft it
   offers Replace/Discard.

## What to record

Append to `logs/development-log.md`: OS build, Xcode build, what worked, every
divergence from the web behaviour with the screen and the repro. Fix forward and
tick `logs/parity-ledger.md`.

## Known first-run risks

- Photos picker returns HEIC; `ImageProcessing` transcodes to JPEG. If a file
  still bounces at the bucket, check the MIME the picker reported.
- `glassEffect` requires the iOS 26 SDK; on Xcode 16 the material fallback renders.
- If OAuth returns to Safari instead of the app, the redirect URL in Supabase is
  wrong or the `vizion` scheme is missing from Info.plist (`project.yml`).

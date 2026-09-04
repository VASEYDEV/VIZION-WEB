# Runbook — TestFlight and the App Store

## Before archiving

- [ ] `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` bumped in `project.yml`; CHANGELOG section written.
- [ ] Icon Composer `.icon` added to the asset catalog (Liquid Glass light/dark/clear/tinted).
- [x] `PrivacyInfo.xcprivacy` present (`App/VIZION/Resources/`): UserDefaults
      `CA92.1` and file timestamp `C617.1`; no tracking; collected types email,
      name, user id, user content, photos, usage data — all linked, none for
      tracking. Keep it in step with the App Store Connect labels below.
- [ ] Companion patch deployed to production; `VIZION_API_BASE_URL` = production.
- [x] Sign in with Apple (guideline 4.8) — shipped natively via Supabase's
      id-token grant (ADR-0006). Before submitting, confirm: the App ID carries
      the capability, Supabase's Apple provider lists `ai.vasey.vizion`, the
      `APPLE_*` env is set on production, and deleting an account revokes the
      Apple token (guideline 5.1.1(v)) — watch for the revoke in the server log.
- [ ] Account deletion verified end-to-end on device.
- [ ] Both themes, Dynamic Type at XXL, VoiceOver pass on every screen.

## Archive → TestFlight

Xcode → Product → Archive → Distribute → App Store Connect → Upload. Internal
testers first; external requires a beta review with a test account + notes.

## App Store Connect

- Name **VIZION**, subtitle "Prompt studio for every model", category Productivity.
- Screenshots on a 6.9" device (sign-in, composer, result, library, settings).
- Privacy nutrition labels: Contact info (email, name) · User content (prompts,
  photos when attached) · Identifiers (user id) · Usage data (the per-user model
  ledger behind the cost cap) — all linked to the user, none for tracking. Same
  set as `PrivacyInfo.xcprivacy`.
- Review notes: a test account, one configured model, and a sentence on what the
  app does with photos.
- Support URL: https://vasey.ai · Marketing URL optional.

## After approval

Tag `v<version>` on `main`; the CHANGELOG section is the release note.

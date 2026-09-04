# Runbook — TestFlight and the App Store

## Before archiving

- [ ] `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` bumped in `project.yml`; CHANGELOG section written.
- [ ] Icon Composer `.icon` added to the asset catalog (Liquid Glass light/dark/clear/tinted).
- [ ] `PrivacyInfo.xcprivacy` present (Required Reason API: UserDefaults `CA92.1`; no tracking; data types: email, user content).
- [ ] Companion patch deployed to production; `VIZION_API_BASE_URL` = production.
- [ ] Sign in with Apple decision: guideline 4.8 requires an equivalent privacy-preserving option when third-party social logins are offered. Either add Sign in with Apple (Supabase supports it natively) or rely on magic link/password satisfying "the app's own account system" — confirm with current guideline text before submission.
- [ ] Account deletion verified end-to-end on device.
- [ ] Both themes, Dynamic Type at XXL, VoiceOver pass on every screen.

## Archive → TestFlight

Xcode → Product → Archive → Distribute → App Store Connect → Upload. Internal
testers first; external requires a beta review with a test account + notes.

## App Store Connect

- Name **VIZION**, subtitle "Prompt studio for every model", category Productivity.
- Screenshots on a 6.9" device (sign-in, composer, result, library, settings).
- Privacy nutrition labels: Contact info (email) · User content (prompts, photos
  when attached) · Identifiers (user id) — all linked to the user, none for tracking.
- Review notes: a test account, one configured model, and a sentence on what the
  app does with photos.
- Support URL: https://vasey.ai · Marketing URL optional.

## After approval

Tag `v<version>` on `main`; the CHANGELOG section is the release note.

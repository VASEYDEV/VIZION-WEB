# Runbook — Supabase configuration for the iOS app

The app uses the SAME project as the web app; no schema changes are needed.

1. **Auth → URL Configuration → Redirect URLs**: add `vizion://auth/callback`.
   Keep the web callback (`https://<domain>/auth/callback`).
2. **Auth → Providers**: Google and GitHub are already configured for the web;
   nothing changes — the app requests them through the same Supabase OAuth URL
   with PKCE. (Google may require the app's bundle id `ai.vasey.vizion` on the
   OAuth client if you later switch to native Google sign-in; not needed now.)
3. **Auth → Email**: the magic-link template's `{{ .ConfirmationURL }}` works
   as-is; Supabase appends the `vizion://` redirect the app asked for.
4. **`app_settings` row 1** must stay readable by `anon` (the web sign-in page
   already relies on it) so the app can show "registrations closed".
5. Values for `Config/Secrets.xcconfig`: Project URL and the **anon/publishable**
   key from Settings → API. Never the service role key.

## Web deployment (companion patch)

Apply `docs/companion/0001-native-bearer-auth-and-account-deletion.patch` to
`SeanVasey/vizion`, run its gate (`npm run lint && npm run typecheck && npm test`),
merge, deploy. `SUPABASE_SERVICE_ROLE_KEY` must be set on Vercel for
`DELETE /api/account` (it already is for the web deletion route).

## Closed registration and OAuth

Magic links honour the owner's open-access switch (`shouldCreateUser`); Supabase
OAuth cannot be told "no new accounts". The app therefore removes an account that
a Google/GitHub sign-in minted while access was closed (`DELETE /api/account`
from the companion patch, then sign-out). To hard-enforce it at the source,
also turn off **Authentication → Providers → Allow new users to sign up** in
the Supabase dashboard whenever access is closed; turn it back on with
open access.


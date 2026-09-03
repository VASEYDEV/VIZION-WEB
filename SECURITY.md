# Security policy — VIZION for iOS

## Reporting

Email security@vasey.ai. Please do not open public issues for vulnerabilities.
Expect an acknowledgement within 72 hours.

## Posture

- **Model keys never exist in the app.** Every model call is proxied by the
  deployed VIZION web API (`/api/enhance`, `/api/media`) which holds the keys,
  enforces the per-user rate limit and daily cost cap, and writes the usage
  ledger. The app cannot reach a provider directly.
- **Authentication is Supabase Auth** through `supabase-swift`: magic link,
  email+password (12+ chars, three classes), GitHub and Google via PKCE in an
  `ASWebAuthenticationSession`. Sessions persist in the Keychain. The JWT (≤ 7 d,
  rotated by the SDK) reaches the web API as a Bearer header and is verified
  server-side against Supabase before any route runs (companion patch).
- **Row Level Security** on every table scopes data to the signed-in user;
  writes additionally filter on `user_id`.
- **Configuration lives in a gitignored xcconfig**: the Supabase URL and anon
  key (public by design under RLS) and the API base URL. Nothing else.
- **Local storage is convenience only** (draft, preferences, last result);
  the server is the source of truth. On a shared device an account switch
  drops the previous user's draft and result.
- **Attachments** are sent to the selected model for analysis only when the
  user attaches them; "Analyze without keeping" stores nothing. Stored media
  lives in the user's private bucket path (50 MB) and is removable in Settings.
- **Account deletion** is in-app (`DELETE /api/account`) and irreversible.
- **No analytics or third-party SDKs** beyond supabase-swift.

## Dependencies

`supabase-swift` (2.x). Review `Package.resolved` on every bump; CI builds the
core on Linux and the app on macOS.

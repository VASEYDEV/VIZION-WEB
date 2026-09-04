# Companion patch for `SeanVasey/vizion`

`0001-native-bearer-auth-and-account-deletion.patch` is a `git diff` against the
web repo's `main` (`404e8ad`, 2026-09-03). It makes the deployed API usable by a
native client (ADR-0003):

| File | Change |
| --- | --- |
| `src/lib/security/bearer.ts` | `bearerToken(header)` — parse `Authorization: Bearer <jwt>` |
| `src/lib/supabase/server.ts` | with a bearer, return a memory-only client whose token is verified via `setSession` → `/auth/v1/user`; cookies untouched |
| `src/lib/supabase/middleware.ts` | `/api/*` + bearer skips the cookie gate; pages unchanged |
| `src/lib/auth/delete-account.ts` | `purgeAccount(admin, userId)` extracted from the form route |
| `src/app/auth/delete-account/route.ts` | calls `purgeAccount` (behaviour unchanged) |
| `src/app/api/account/route.ts` | **new** `DELETE /api/account` → 204/401/429/503/500 |
| `tests/unit/middleware-gate.test.ts` | +3 cases for the bearer transport |
| `tests/unit/account-route.test.ts` | **new** 4 cases |

Validated in this repo's session against the web clone: `npm run typecheck` ✓,
`eslint` ✓, `prettier --check` ✓, and the affected Vitest files (78 tests) ✓;
`git apply --check` against a clean `origin/main` worktree ✓.

## `0002-sign-in-with-apple.patch`

A `git diff` on top of `0001` (same base, `404e8ad`). It is what Sign in with
Apple needs on the server (ADR-0006); the sign-in itself is Supabase's
id-token grant and needs nothing from the web app.

| File | Change |
| --- | --- |
| `supabase/migrations/…_auth_method_apple.sql` | `alter type auth_method add value 'apple'` |
| `supabase/migrations/…_apple_sign_in.sql` | `handle_new_user()` maps `apple`; `apple_refresh_tokens` table (RLS: own row; service role revokes) |
| `src/lib/auth/apple.ts` | **new** ES256 client secret, code → refresh-token exchange, revoke |
| `src/app/api/auth/apple/route.ts` | **new** `POST /api/auth/apple` → 204/400/401/429/502/503 |
| `src/lib/auth/delete-account.ts` | `purgeAccount` revokes the Apple token FIRST; a failed revoke stops the deletion |
| `src/lib/supabase/database.types.ts` | `apple` in the `auth_method` union; the new table |
| `src/components/settings/SettingsPanel.tsx` | "Connected with Apple" |
| `SECURITY.md` | what the token row is and who may read it |
| `tests/unit/apple-auth.test.ts` · `apple-code-route.test.ts` · `delete-account.test.ts` | **new** 22 cases |
| `tests/unit/account-route.test.ts` · `delete-account-route.test.ts` | admin mock gains the token read |

Server env (Vercel): `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_CLIENT_ID`
(= `ai.vasey.vizion`), `APPLE_PRIVATE_KEY` (the `.p8`, `\n`-escaped). Without
them the route answers 503 and deletion logs and proceeds — a person asking for
their account to be deleted must never be blocked by a server env gap.

Validated in this repo's session against a worktree of the web `main` with
`0001` applied: `npm run lint` ✓ · `tsc --noEmit` ✓ · `prettier --check` ✓ ·
`vitest run` (111 files, 1500 tests) ✓ · `git apply --check` of `0001` then
`0002` on a clean `404e8ad` ✓.

## Apply

```bash
cd vizion
git checkout -b feat/native-bearer-auth
git apply /path/to/vizion-web/docs/companion/0001-native-bearer-auth-and-account-deletion.patch
git apply /path/to/vizion-web/docs/companion/0002-sign-in-with-apple.patch
npm run lint && npm run typecheck && npm test
git add -A && git commit -m "feat(api): bearer-token sessions for the native app + DELETE /api/account"
```

Then push the two migrations (`supabase db push`), deploy (a preview is fine
for device testing) and point the app's `VIZION_API_BASE_URL` at it.

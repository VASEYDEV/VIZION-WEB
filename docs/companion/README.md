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

## Apply

```bash
cd vizion
git checkout -b feat/native-bearer-auth
git apply /path/to/vizion-web/docs/companion/0001-native-bearer-auth-and-account-deletion.patch
npm run lint && npm run typecheck && npm test
git add -A && git commit -m "feat(api): bearer-token sessions for the native app + DELETE /api/account"
```

Then deploy (a preview is fine for device testing) and point the app's
`VIZION_API_BASE_URL` at it.

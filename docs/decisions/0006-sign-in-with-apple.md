# ADR-0006 — Sign in with Apple via Supabase's id-token grant

**Status:** accepted · 2026-09-04 · companion patch `0002-sign-in-with-apple.patch`

## Context

The app offers Google and GitHub. App Store Review Guideline 4.8 requires an
equivalent privacy-preserving login option alongside third-party social logins,
and the practical reading is: ship Sign in with Apple. The web app has no such
requirement and does not offer it, so this is the first place the port
deliberately does MORE than the web (CLAUDE.md §1: the web wins unless an ADR
says otherwise — this is that ADR).

Two ways to do it:

1. **Web flow** — Supabase's OAuth URL for `apple` in an
   `ASWebAuthenticationSession`, exactly as GitHub and Google work here.
2. **Native flow** — `SignInWithAppleButton` / `ASAuthorizationController`, then
   hand the identity token to Supabase's id-token grant.

## Decision

The **native flow**. `AuthenticationServices` mints the credential, and
`SupabaseService.signInWithApple(idToken:nonce:)` calls
`auth.signInWithIdToken(credentials: .init(provider: .apple, …))`. Supabase
verifies the token against Apple's public keys, checks the nonce, and mints
the session.

- **Nonce**: `SignInNonce` (VizionCore) is 32 random bytes as hex. Apple's
  request carries its SHA-256; Supabase gets the raw value and compares. A
  token minted for one request cannot be replayed into another sign-in.
- **The name**: Apple sends it ONCE, on the first authorisation, and only to
  the app — the identity token has no name claim, so the web's
  `handle_new_user()` has nothing to copy. `AppEnvironment.seedFullName`
  writes it into `profiles.full_name`, never over a name already there.
- **Closed registration**: the id-token grant has no `shouldCreateUser`, so
  Apple sign-in reuses the OAuth rule exactly — the sign-in screen stamps
  `oauthAttemptStartedAt`, and `purgeIfMintedWhileClosed` removes an account
  minted after that instant while access is closed.
- **Revocation**: Apple requires an app offering Sign in with Apple to revoke
  the user's tokens when the account is deleted (Guideline 5.1.1(v)).
  Revocation needs a refresh token, which only the authorization code can buy,
  so the app posts that code to `POST /api/auth/apple` (companion patch) and
  `purgeAccount` revokes it before deleting anything.
- **`auth_method`**: the companion migration adds the `apple` enum label and
  maps it in `handle_new_user()`.

## Consequences

- No web-auth session, no redirect, no `vizion://` round trip for this method:
  the sheet is the system's and stays in the app. It is also the one method
  that cannot work in the simulator against a real Apple ID.
- A new entitlement (`com.apple.developer.applesignin`) and an App ID
  capability; automatic signing adds it on the first device build.
- Supabase's Apple provider needs the bundle id `ai.vasey.vizion` in its
  authorised client ids (runbook `supabase-config.md`). The provider's
  Services ID / secret is only needed for the web flow, which we do not use.
- Without the companion patch deployed the sign-in still works; only the
  revocation bookkeeping is missing, and `POST /api/auth/apple` 404s into the
  best-effort `try?`.
- Anything Apple-shaped stays out of `VizionCore` except the nonce, which is
  pure and Linux-testable.

## Rejected

**The web flow** (option 1) would need a Services ID, a separate client secret
rotation, and a Safari round trip for a method whose whole point is that it is
native and silent. It also cannot return the name at all.

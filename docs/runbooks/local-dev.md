# Runbook — local development

## Mac (the real thing)

```bash
git clone git@github.com:vaseydev/vizion-web.git && cd vizion-web
make bootstrap                      # tools + Config/Secrets.xcconfig + xcodegen
$EDITOR Config/Secrets.xcconfig     # SUPABASE_URL, SUPABASE_ANON_KEY, VIZION_API_BASE_URL, VIZION_TEAM_ID
make open
```

Select your iPhone as the run destination (developer beta requires the matching
Xcode beta), press Run. Automatic signing uses `VIZION_TEAM_ID`.

### The first build — expected reconcile list

`App/VIZION/Sources/Services/*` was written against supabase-swift 2.x from
memory. If the resolved version disagrees, the fixes are mechanical and local:

| Call | If it fails, look for |
| --- | --- |
| `SupabaseClientOptions.AuthOptions(redirectToURL:flowType:)` | the current init labels |
| `auth.signInWithOTP(email:redirectTo:shouldCreateUser:)` | same |
| `auth.getOAuthSignInURL(provider:redirectTo:)` · `auth.session(from:)` | same |
| `auth.update(user: UserAttributes(...))` | same |
| PostgREST `.is(_:value: nil)` · `.not(_:operator: .is, value: "null")` · `.ilike(_:pattern:)` · `.contains(_:value:)` | `.filter(_:operator:value:)` accepts any operator as a string |
| `storage.from(...).upload(_:data:options:)` · `getPublicURL(path:)` · `createSignedURL(path:expiresIn:)` | same |
| `AnyJSON` cases | `.string/.bool/.integer/.double/.null/.array/.object` |
| `rpc(_:params:)` returning a scalar | decode as `String`/`Bool` via `.execute().value` |

Everything else is plain SwiftUI/Foundation and should build on Xcode 16.4+ and
Xcode 26.

## Linux / no Mac

```bash
# one-time toolchain
curl -sSLo swift.tgz https://download.swift.org/swift-6.3.3-release/ubuntu2404/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-ubuntu24.04.tar.gz
sudo mkdir -p /opt/swift && sudo tar -xzf swift.tgz -C /opt/swift --strip-components=1
export PATH=/opt/swift/usr/bin:$PATH
make core-test
```

Only `Packages/VizionCore` builds here; that is the point of the split.

## Fonts

`App/VIZION/Resources/Fonts/*.ttf` were converted from the web's WOFF2 with
fontTools (`python3 -m pip install fonttools brotli`; `TTFont(f).flavor=None;
save()`). They are latin subsets — swap in full TTFs from the same OFL families
before non-latin UI matters.

## Regenerating the icon

`scripts/` has no icon generator yet; the PNGs were composed from
`Design/brand/vizion-glyph.svg` with Pillow (Void plate, Laser glyph, the Icon
Composer offset `translate(133.12,165.66) scale(0.74)`). For the Liquid Glass
icon, open Icon Composer and import `Design/brand/vizion-icon-foreground-*.svg`
and `vizion-icon-bg-*.svg` as layers.

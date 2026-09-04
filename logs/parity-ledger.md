# Parity ledger — web feature → iOS status

Legend: ✅ ported · 🟡 partial / simplified · ⬜ not yet · ➖ not applicable natively

## Auth & gate
| Feature | Status | Note |
| --- | --- | --- |
| Magic link sign-in | ✅ | `vizion://auth/callback` return |
| Email + password sign-in | ✅ | |
| GitHub / Google OAuth (PKCE) | ✅ | `ASWebAuthenticationSession` |
| Set-password onboarding gate | ✅ | |
| Closed-access (owner switch) | ✅ | owner = recorded claimant only; `OWNER_EMAIL` env is server-only |
| Sign in with Apple | ✅ | Native id-token grant (ADR-0006) — the app does MORE than the web here (guideline 4.8) |
| Session refresh ≤ 7 d | ✅ | SDK |

## Enhance
| Feature | Status | Note |
| --- | --- | --- |
| Six modes, mode rig with lens + blurb | ✅ | |
| Target picker grouped by developer + marks | ✅ | |
| Auto routing + budget preference | ✅ | |
| Thinking dial per target | 🟡 | segmented ladder; press-and-hold capsule (ADR-0012/0014) ⬜ |
| Shape rail (Reformat) / Depth rail (Condense, Expand) | ✅ | |
| SSE streaming, monotonic ticker, cancel | ✅ | |
| Result: copy · use · save · share · export (md/json/txt) | ✅ | |
| Duplicate detection → save as new version | ✅ | |
| Polish per-change revert, persisted with the result | ✅ | |
| Clarify questions → answered re-run | ✅ | |
| Refine chips (shorter · detail · tone) | ✅ | |
| Assumptions · target notes · truncated · salvaged · estimated | ✅ | |
| Original collapsible with removed-side diff | ✅ | |
| Daily-cap banner | ✅ | |
| Templates | ✅ | |
| Paste from clipboard | ✅ | |
| `?draft=` intake with conflict offer | ✅ | `vizion://enhance?draft=` |
| Result survives navigation/relaunch, per account | ✅ | |
| Keyboard action bar / horizon decoration | ➖ | native keyboard; ambient ground instead |
| Offline outbox for saves | ⬜ | error + retry today |
| Haptics | ✅ | native (the web could not) |

## Attachments
| Feature | Status | Note |
| --- | --- | --- |
| Privacy notice + keep-by-default | ✅ | |
| Image attach via Photos | ✅ | HEIC → JPEG |
| Video frame capture / audio metadata | ⬜ | |
| Roles: reference · extract · describe · style · generate | ✅ | |
| Reserve → upload → commit pipeline | ✅ | |
| Analysis via `/api/media` with intent, Auto, fallback notice | ✅ | |
| Reference context blocks on the enhance request | ✅ | |
| Generation prompt (Midjourney/Runway/Sora/Kling/Audio) | ✅ | |
| Syntax highlighting of the generated prompt | ⬜ | |
| Drag & drop / paste files | ➖ | Photos picker instead |

## Library
| Feature | Status | Note |
| --- | --- | --- |
| Server-side filter (q/model/mode/tag/collection/view/sort) + keyset paging | ✅ | |
| Facets (models present, tags, collections) | ✅ | |
| Favorites · archive · soft delete + undo · Recently deleted · delete forever | ✅ | |
| Rename · tags · collections CRUD · move | ✅ | |
| Swipe actions | ⬜ | all actions in the context menu (swipe needs a List host) |
| CI proof of the app target | ✅ | `xcodebuild` builds + runs the app unit tests on the iOS Simulator (macOS runner) since `5e5d95d` |
| Developer-accent card field | ✅ | |
| Activity feed | ✅ | |
| Drafts: save from New prompt, resume (move), edit in place (OCC), delete, search body | ✅ | |
| Prompt detail: history, restore, compare any two, revise → version | ✅ | |
| Share logging | ✅ | |

## Settings
| Feature | Status | Note |
| --- | --- | --- |
| Identity (full name, display name rule, avatar) | 🟡 | center-square crop; interactive cropper ⬜ |
| Email change (verified) · password set/change · connection badge · sign out | ✅ | pending-email uses `user.newEmail` |
| Default model with Auto clear (+ live store write-through, rollback) | ✅ | |
| Theme (dark/light/system) · reduced effects | ✅ | |
| Clear device draft · stored media manager · export JSON · delete account | ✅ | deletion needs the companion endpoint |
| Owner console (open access, accent strength) | ✅ | visible to the recorded claimant |
| About | ✅ | |

## Platform
| Feature | Status | Note |
| --- | --- | --- |
| App icon (opaque, dark tile) + tinted | ✅ | Liquid Glass `.icon` ⬜ |
| Fonts (Bebas Neue, Reddit Sans 400/500/600, JetBrains Mono) | 🟡 | latin subsets |
| Liquid Glass (iOS 26+) with material fallback | ✅ | gated |
| Universal links | ⬜ | scheme links work |
| Privacy manifest | ⬜ | M6 |
| Widgets / Shortcuts App Intents | ⬜ | URL scheme covers the Shortcut today |

# API contract the app depends on

The deployed web app (`SeanVasey/vizion`, Vercel) is the backend for every model
call. This document is the wire contract as of `404e8ad` plus the companion patch.

## Authentication

Every request: `Authorization: Bearer <supabase access_token>`. The server
(`src/lib/supabase/server.ts`, companion patch) verifies the token via
`auth.setSession` → `/auth/v1/user` before any route reads `auth.getUser()`.
A missing/invalid/expired token → `401 {"error": …}`. Cookies are never used by
the app.

## POST /api/enhance

Body (`EnhanceRequest`, nil fields omitted):

```json
{ "input": "…", "mode": "clarify|polish|expand|condense|reformat|target",
  "target": "<model id>", "auto": true, "autoPreference": "quality|balanced|budget",
  "format": "json|markdown|steps|fewshot|xml", "length": "short|medium|long",
  "thinkingLevel": "minimal|low|medium|high|xhigh|max",
  "refine": { "kind": "shorter|detail|tone|answers", "baseInput": "…" },
  "mediaContext": ["Visual reference (name): …"] }
```

Gates (plain JSON with real statuses): 400 unknown mode/target/level/format/length/refine ·
413 input > 20 000 chars · 429 rate/cap (`capReached: true`) · 503 provider not
configured (`notConfigured: true`) · 403 owner closed access.

200 → `text/event-stream`, frames `data: {json}\n\n`:

| type | fields |
| --- | --- |
| `status` | `step` (queued/connecting/generating/parsing/diffing), `label` |
| `thinking` | `text` (reserved; overrides the step label) |
| `delta` | `text` — decoded output characters, in order |
| `usage` | `tokenIn`, `tokenOut`, `costUsd?`, `snapshot?` — a snapshot is a provider placeholder and may only raise the counters |
| `done` | `result` — `EnhanceResult` below |
| `error` | `status`, `error`, `notConfigured?`, `capReached?` |

`EnhanceResult`: `output`, `rationale`, `diff` (segments `{op: equal|added|removed, text}` or `null` over budget),
`tokenIn`, `tokenOut`, `modelUsed`, `costUsd`, `usage {todayCost, capUsd}`, optional
`assumptions[]`, `targetNotes`, `title`, `questions[]` (Clarify), `salvaged`,
`truncated`, `usageEstimated`, `resolvedTarget` + `resolvedReason` (Auto only).

## POST /api/media

Body: `{ "dataUrl": "data:image/jpeg;base64,…", "target": "<id>", "intent":
"reference|describe|style|extract_text", "auto": true, "autoPreference": "…" }`.
Images only (≤ ~5 MB decoded). Same gates as enhance.

200: `{ "intent", "attributes": {subject, composition, palette[], lighting, style, mood, source},
"description", "text" (extract_text), "modelUsed", "fallbackFrom"?,
"usage": {target, tokenIn, tokenOut, costUsd, todayCost, capUsd, estimated?} }`.

## DELETE /api/account (companion patch)

204 deleted · 401 no session · 429 > 3/hour · 503 service role unconfigured · 500 failed.
The app signs out locally on 204.

## Direct Supabase (user JWT, RLS)

Tables: `profiles`, `prompts`, `prompt_versions`, `collections`, `drafts`,
`activity_events`, `media_assets`, `app_settings` (row 1, anon-readable).
RPCs: `library_save_prompt`, `library_add_version`, `media_reserve`, `media_commit`,
`update_app_settings`, `claim_app_ownership`. Storage: `avatars` (public read,
`{uid}/avatar.png`), `media` (private, `{uid}/<uuid>.<ext>`).

Keyset paging: `order(sort, id desc) limit 31`, next page via
`or(col.lt."v",and(col.eq."v",id.lt.<uuid>))` — values quoted, id UUID-pinned
(`LibraryPaging`). Content hash for duplicates: sha256 over
`input ∥ 0x1F ∥ output ∥ 0x1F ∥ mode ∥ 0x1F ∥ target`, hex.

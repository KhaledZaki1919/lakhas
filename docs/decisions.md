# Architecture Decision Records

Short ADRs. Status values: **Accepted** (from the brief), **Proposed** (awaiting approval), **Superseded**.

---

### ADR-001 — Monorepo, XcodeGen, Cloudflare Workers + Hono
**Status:** Accepted (brief §2). Layout: `/ios /backend /shared /admin /docs`.

### ADR-002 — Native structured outputs instead of forced `tool_choice`
**Status:** Accepted (2026-10-11). The brief §2 has been updated to match.
**Context:** The brief asks every AI call to force a single tool call through `tool_choice`. On current models, `claude-sonnet-5-5` (our `MODEL_ADVANCED`) and `claude-opus-5-5` reject `tool_choice` `any`/`tool` with HTTP 400.
**Decision:** Use structured outputs, `client.messages.parse({ output_config: { format: zodOutputFormat(Schema) } })`, for all AI calls on both models. The zod schema is the single source; it also generates `/shared/schemas/*.json`. Keep server-side zod validation + one retry as defense in depth, and check `stop_reason` (refusal / max_tokens) before parsing.
**Consequences:** Same guarantees as the brief intended, with one code path. Prompt files describe the output schema in prose instead of as a tool.

### ADR-003 — Model names and limits in a `config` table
**Status:** Accepted (brief §2, §5). D1 `config` table, KV-cached for 60s, editable in admin. Defaults: `MODEL_STANDARD = claude-haiku-5-5`, `MODEL_ADVANCED = claude-sonnet-5-5`.

### ADR-004 — Quota counters in D1, not KV
**Status:** Proposed.
**Context:** KV is eventually consistent and limits writes per key to about 1/s. Parallel requests could exceed quotas, and dedupe could miss.
**Decision:** `quota_events` table with PK `(device_id, day_key, quota_type, input_hash)`. Reserve with a conditional `INSERT … SELECT … WHERE count < limit`, commit on success, delete on failure. D1 serializes writes, so this is race-free. KV holds only the AI result cache (same-day retries) and the config cache. Per-IP burst limiting uses the Workers **Rate Limiting binding**.
**Consequences:** One D1 write per AI request (cheap). Dedupe and "failed requests don't count" are exact.

### ADR-005 — Certificate pinning strategy
**Status:** Proposed (see open question Q2).
**Decision:** Pin SPKI hashes of the CA chain Cloudflare uses for our edge cert (primary + backup CAs), checked in `URLSessionDelegate`. A rotation runbook goes in `/docs/runbooks/pinning.md`. Revisit leaf-key pinning if we move to a Cloudflare plan with custom certificates.

### ADR-006 — App Attest dev bypass
**Status:** Proposed.
**Decision:** Client bypass code exists only under `#if DEBUG`. The server honors `X-Attest-Bypass` only when `ENVIRONMENT == "dev"` and the token matches a dev-only secret that isn't configured in production. A Release-build test asserts the bypass symbol is absent.

### ADR-007 — Admin protected by Cloudflare Access
**Status:** Proposed (Q14). Access policy on `/admin/*`, plus the Worker verifies the `Cf-Access-Jwt-Assertion` JWT (defense in depth).

### ADR-008 — SVG illustrations rasterized server-side
**Status:** Proposed.
**Decision:** Sanitize the SVG with an allow-list parser, then rasterize it to a 512×512 PNG with `resvg-wasm` in the Worker. Store both in R2; iOS displays the PNG. This avoids an SVG renderer dependency on iOS.

### ADR-009 — Offline food DB as bundled SQLite, not SwiftData
**Status:** Proposed. Static reference data with FTS5 search, opened read-only with the SQLite C API, and generated from the D1 seed at build time.

### ADR-010 — Logs snapshot names and nutrition values
**Status:** Proposed. `MealItem`, `SetLog` and `WorkoutSession` store copies of names and per-100g values plus a stable id, never live relationships to editable entities. Editing foods, recipes or programs can't alter history.

### ADR-011 — Product defaults resolved in Phase 0
**Status:** Accepted (2026-10-11).
- **Protein at BMI ≥ 30:** the reference weight is the weight at BMI 25 for the user's height (`25 × m²`). No goal-weight question in onboarding; an optional goal weight in My Goals overrides it.
- **"Correct with AI":** separate Pro-only quota type `correct`, 10/day, under the global per-device cap.
- **Leftover photo:** part of the same photo scan, so one `photo` quota covers both images.
- **Pace options:** lose 0.25 / 0.5 / 0.75 / 1.0 kg/week; gain 0.25 / 0.5 kg/week; maintain 0.
- **Arabic names for USDA foods and exercises:** machine-translated at seed time, stored with `name_ar_source = 'machine_translated'`, and listed in an admin review queue.
- **Delete my data:** `transactions` and `referral_attributions` are kept for accounting with `device_id` set to NULL. All other device data is deleted. The Privacy Policy will say so.

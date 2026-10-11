# Architecture Decision Records

Short ADRs. Status values: **Accepted**, **Proposed** (awaiting approval), **Superseded**, **Withdrawn**.

---

### ADR-001 — Monorepo, XcodeGen, Cloudflare Workers + Hono
**Status:** Accepted. Layout: `/ios /backend /shared /admin /docs`.

### ADR-002 — Native structured outputs instead of forced `tool_choice`
**Status:** Accepted (2026-10-11).
**Context:** The original brief asked every AI call to force a single tool call through `tool_choice`. On current models, `claude-sonnet-5-5` (our `MODEL_ADVANCED`) and `claude-opus-5-5` reject `tool_choice` `any`/`tool` with HTTP 400.
**Decision:** Use structured outputs, `client.messages.parse({ output_config: { format: zodOutputFormat(Schema) } })`, for all AI calls on both models. The zod schema is the single source; it also generates `/shared/schemas/*.json`. Keep server-side zod validation + one retry as defense in depth, and check `stop_reason` (refusal / max_tokens) before parsing.

### ADR-003 — Model names and limits in a `config` table
**Status:** Accepted. D1 `config` table, KV-cached for 60s, editable in admin. Defaults: `MODEL_STANDARD = claude-haiku-5-5`, `MODEL_ADVANCED = claude-sonnet-5-5`.

### ADR-004 — Cost-cap counters in D1, not KV
**Status:** Accepted (wording amended by ADR-015: "quotas" are now single-tier cost caps).
**Decision:** `cap_events` table with PK `(device_id, day_key, cap_type, input_hash)`. Reserve with a conditional `INSERT … SELECT … WHERE count < limit`, commit on success, delete on failure. D1 serializes writes, so this is race-free. KV holds only the AI result cache (same-day retries) and the config cache. Per-IP burst limiting uses the Workers Rate Limiting binding.

### ADR-005 — Certificate pinning strategy
**Status:** Accepted (2026-10-11).
**Decision:** Pin SPKI hashes of the CA chain Cloudflare uses for our edge certificate (primary + backup CAs), checked in a `URLSessionDelegate`. A rotation runbook goes in `/docs/runbooks/pinning.md`. Pins are delivered in the app build; a pin change ships as a new IPA.

### ADR-006 — App Attest dev bypass
**Status:** Superseded by ADR-013. App Attest needs the paid Developer Program and isn't available to sideloaded free-team apps.

### ADR-007 — Admin protected by Cloudflare Access
**Status:** Accepted (2026-10-11). Access policy on `/admin/*`, plus the Worker verifies the `Cf-Access-Jwt-Assertion` JWT (defense in depth).

### ADR-008 — SVG illustrations rasterized server-side
**Status:** Proposed.
**Decision:** Sanitize the SVG with an allow-list parser, then rasterize it to a 512×512 PNG with `resvg-wasm` in the Worker. Store both in R2; iOS displays the PNG.

### ADR-009 — Offline food DB as bundled SQLite, not SwiftData
**Status:** Proposed. Static reference data with FTS5 search, opened read-only with the SQLite C API, and generated from the D1 seed at build time.

### ADR-010 — Logs snapshot names and nutrition values
**Status:** Proposed. `MealItem`, `SetLog` and `WorkoutSession` store copies of names and per-100g values plus a stable id, never live relationships to editable entities.

### ADR-011 — Product defaults resolved in Phase 0
**Status:** Accepted (2026-10-11).
- **Protein at BMI ≥ 30:** reference weight = weight at BMI 25 for the user's height (`25 × m²`); an optional goal weight in My Goals overrides it.
- **AI corrections:** their own cap type `correct`, 10/day, under the global per-device cap.
- **Leftover photo:** part of the same photo scan (one `photo` count for both images).
- **Pace options:** lose 0.25 / 0.5 / 0.75 / 1.0 kg/week; gain 0.25 / 0.5 kg/week; maintain 0.
- **Arabic names for USDA foods and exercises:** machine-translated at seed time, stored with `name_ar_source = 'machine_translated'`, listed in an admin review queue.
- ~~Delete my data keeps purchase/referral records~~ (withdrawn with ADR-015: there are no purchases or referrals; deletion removes everything).

### ADR-012 — Personal sideloading; unsigned IPA from CI
**Status:** Accepted (2026-10-11).
**Context:** The app is for personal use, installed with Sideloadly from Windows using a free Apple ID. No App Store, TestFlight or paid Developer Program.
**Decision:**
- **CI:** GitHub Actions `macos` runners build on every push to `main`. The workflow:
  1. generates the project with XcodeGen;
  2. runs the unit tests on the Simulator;
  3. builds Release with `CODE_SIGNING_ALLOWED=NO`;
  4. embeds entitlements with an **ad-hoc signature** (`codesign --force --sign - --entitlements …`, inner extensions first). This needs no certificate and no secret. It's done so that Sideloadly can read the requested entitlements (App Group) when it re-signs. Without it, an unsigned binary carries no entitlements;
  5. zips `Payload/Lakhas.app` into an `.ipa` and uploads it as a workflow artifact.
- **Two variants:** `Lakhas-full.ipa` (with extensions) and `Lakhas-lite.ipa` (app only, one App ID).
- **Not used:** signing secrets, TestFlight, App Store Connect.
**Consequences:** Free-team apps expire after 7 days and need a Sideloadly refresh. Data survives a refresh as long as the bundle ID and Apple ID stay the same (see ADR-016 for the backup).

### ADR-013 — Device access tokens with HMAC request signing (replaces App Attest)
**Status:** Accepted (2026-10-11).
**Decision:**
- **Token creation:** the admin creates a token per device: `lk1_<tokenId>_<secret>`, where `secret` is 32 random bytes in base64url. It's shown once, as text and a QR code. D1 stores `token_id`, a label, and the secret **encrypted with AES-GCM** under the Worker secret `TOKEN_ENC_KEY`. A D1 leak alone doesn't expose secrets.
- **Client storage:** the app asks for the token on first launch, calls `GET /v1/device` to verify it, and stores it in the Keychain (`AfterFirstUnlockThisDeviceOnly`, app's default access group).
- **Signing:** every request carries `X-Lakhas-Token-Id`, `X-Lakhas-Timestamp` (Unix ms), `X-Lakhas-Nonce` (16 random bytes, base64url) and `X-Lakhas-Signature`. The signature is base64url(HMAC-SHA256(secret, `"LK1\n" + METHOD + "\n" + path?query + "\n" + timestamp + "\n" + nonce + "\n" + hex(SHA256(body))`)).
- **Verification:** the server rejects skew > 5 min. It rejects a nonce already seen for that token: D1 `request_nonces` with PK `(token_id, nonce)`, purged after 10 min by cron. It compares signatures in constant time.
- **Revocation:** the admin can revoke a token. Requests then return `401 token_revoked`, and the app clears the Keychain item and shows the token screen.
- **Shared test vectors** in `/shared/test-vectors/signing.json` are used by both the Swift and TypeScript tests.
**Consequences:** No secret is compiled into the IPA. A stolen token is limited by its device caps and revocable. The token ID is the server-side device identity, replacing the client-generated UUID.

### ADR-014 — Free Apple ID capability fallbacks
**Status:** Accepted (2026-10-11); App Group behavior must be verified on device with the Phase 1 capability probe. Findings: `docs/sideloading.md`.
**Decision:**
- **Extensions behind a flag.** `LAKHAS_EXTENSIONS` (Swift active compilation condition + XcodeGen target inclusion) builds the widget and share extensions. The lite variant has neither.
- **Runtime App Group resolution.** Re-signing tools may rewrite App Group identifiers per team. The app and widget resolve the real group at runtime:
  1. Read `com.apple.security.application-groups` from `embedded.mobileprovision` in the bundle.
  2. Fall back to the compiled ID.
  3. Fall back to the app's own container. In that case widgets show "Open لخّص to set up widgets".
- **No Keychain sharing.** Only the app reads the token; widgets and the share extension never call the API, so no shared Keychain group is needed.
- **Data protection** is set per file with `FileManager` attributes, so no entitlement is needed.
- **No hardcoded bundle ID or team prefix at runtime.** Use `Bundle.main` values.
- **Share-extension fallback:** in-app "Paste link" (`PasteButton`, no clipboard prompt) and PhotosPicker for screenshots.

### ADR-015 — Single tier; monetization removed
**Status:** Accepted (2026-10-11).
**Decision:** The following are removed, and all former Pro features are enabled for everyone:
- StoreKit, the paywall, and App Store Server Notifications;
- the creator/referral program;
- the support inbox and APNs.

Quotas become per-device daily **cost caps**, set to the old Pro limits: photo 10, recipe 5, text 5, barcode 10, correct 10, global 40. Caps are configurable globally and per device in the admin panel.

### ADR-016 — Local backup export/import instead of iCloud
**Status:** Accepted (2026-10-11).
**Context:** iCloud/CloudKit isn't available to free teams. Re-signing under a different bundle ID or Apple ID creates a fresh, empty app container.
**Decision:** Settings → Backup exports a versioned JSON file (plus photos, zipped) through the share sheet / Files, and imports it back with an idempotent UUID-based merge. A reminder appears if no backup has been made in 14 days.

### ADR-017 — Design system: direction A, Progress in the Today header
**Status:** Accepted (2026-10-11).
**Decision:**
- Direction A "Tahini & Mint" is the final design system (tokens in `docs/design.md`).
- **Tab bar:** Today, Recipes, [+], Explore, Workouts. Progress opens from the Today header, so the "+" is truly centered.
- **Light-mode carbs color** changed from `#C98A1B` to `#A86F0E` to meet the 3:1 minimum for graphics.

### ADR-018 — Remaining Phase 0 questions resolved
**Status:** Accepted (2026-10-11).
- **Build machine:** Windows + GitHub Actions; a Mac only later, optionally (ADR-012).
- **Instagram import:** official oEmbed with a Meta app token; screenshot import is the fallback UX when a link can't be read.
- **Water target:** follows §6 exactly (weight + activity, no height).
- **Explore votes:** the client shows the vote button only after logging the dish; the server enforces one vote per device per dish.
- **Recipe language:** titles and ingredient names in both languages; steps in the language active at import.

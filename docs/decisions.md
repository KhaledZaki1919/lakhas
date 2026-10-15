# Architecture Decision Records

Short ADRs. Status values: **Accepted**, **Proposed** (awaiting approval), **Superseded**, **Withdrawn**.

---

### ADR-001 — Monorepo, XcodeGen, Cloudflare Workers + Hono
**Status:** Accepted. Layout: `/ios /backend /shared /admin /docs`.

### ADR-002 — Native structured outputs instead of forced `tool_choice`
**→ Amended by ADR-020: structured outputs per provider, in the app.**
**Status:** Accepted (2026-10-11).
**Context:** The original brief asked every AI call to force a single tool call through `tool_choice`. On current models, `claude-sonnet-5-5` (our `MODEL_ADVANCED`) and `claude-opus-5-5` reject `tool_choice` `any`/`tool` with HTTP 400.
**Decision:** Use structured outputs, `client.messages.parse({ output_config: { format: zodOutputFormat(Schema) } })`, for all AI calls on both models. The zod schema is the single source; it also generates `/shared/schemas/*.json`. Keep server-side zod validation + one retry as defense in depth, and check `stop_reason` (refusal / max_tokens) before parsing.

### ADR-003 — Model names and limits in a `config` table
**→ Superseded by ADR-020 (settings are local).**
**Status:** Accepted. D1 `config` table, KV-cached for 60s, editable in admin. Defaults: `MODEL_STANDARD = claude-haiku-5-5`, `MODEL_ADVANCED = claude-sonnet-5-5`.

### ADR-004 — Cost-cap counters in D1, not KV
**→ Superseded by ADR-020 (local usage counter, optional daily limit).**
**Status:** Accepted (wording amended by ADR-015: "quotas" are now single-tier cost caps).
**Decision:** `cap_events` table with PK `(device_id, day_key, cap_type, input_hash)`. Reserve with a conditional `INSERT … SELECT … WHERE count < limit`, commit on success, delete on failure. D1 serializes writes, so this is race-free. KV holds only the AI result cache (same-day retries) and the config cache. Per-IP burst limiting uses the Workers Rate Limiting binding.

### ADR-005 — Certificate pinning strategy
**→ Superseded by ADR-020 (no certificate pinning; ATS + system trust).**
**Status:** Accepted (2026-10-11).
**Decision:** Pin SPKI hashes of the CA chain Cloudflare uses for our edge certificate (primary + backup CAs), checked in a `URLSessionDelegate`. A rotation runbook goes in `/docs/runbooks/pinning.md`. Pins are delivered in the app build; a pin change ships as a new IPA.
**Update (2026-10-12):** the API uses the free `*.workers.dev` subdomain (no custom domain). Its chain ends in GTS Root R4, which is pinned, so no change was needed.

### ADR-006 — App Attest dev bypass
**Status:** Superseded by ADR-013. App Attest needs the paid Developer Program and isn't available to sideloaded free-team apps.

### ADR-007 — Admin protected by Cloudflare Access
**→ Withdrawn by ADR-020 (no admin panel).**
**Status:** Accepted (2026-10-11). Access policy on `/admin/*`, plus the Worker verifies the `Cf-Access-Jwt-Assertion` JWT (defense in depth).

### ADR-008 — SVG illustrations rasterized server-side
**→ Withdrawn by ADR-020 (no AI illustrations).**
**Status:** Proposed.
**Decision:** Sanitize the SVG with an allow-list parser, then rasterize it to a 512×512 PNG with `resvg-wasm` in the Worker. Store both in R2; iOS displays the PNG.

### ADR-009 — Offline food DB as bundled SQLite, not SwiftData
**→ Amended by ADR-020: the bundled DB is the only food DB.**
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
**→ Superseded by ADR-020 (no device tokens or request signing).**
**Status:** Accepted (2026-10-11).
**Decision:**
- **Token creation:** the admin creates a token per device: `lk1_<tokenId>_<secret>`, where `secret` is 32 random bytes in base64url. It's shown once, as text and a QR code. D1 stores `token_id`, a label, and the secret **encrypted with AES-GCM** under the Worker secret `TOKEN_ENC_KEY`. A D1 leak alone doesn't expose secrets.
- **Client storage:** the app asks for the token on first launch, calls `GET /v1/device` to verify it, and stores it in the Keychain (`AfterFirstUnlockThisDeviceOnly`, app's default access group).
- **Signing:** every request carries `X-Lakhas-Token-Id`, `X-Lakhas-Timestamp` (Unix ms), `X-Lakhas-Nonce` (16 random bytes, base64url) and `X-Lakhas-Signature`. The signature is base64url(HMAC-SHA256(secret, `"LK1\n" + METHOD + "\n" + path?query + "\n" + timestamp + "\n" + nonce + "\n" + hex(SHA256(body))`)).
- **Verification:** the server rejects skew > 5 min. It rejects a nonce already seen for that token: D1 `request_nonces` with PK `(token_id, nonce)`, purged after 10 min by cron. It compares signatures in constant time.
- **Revocation:** the admin can revoke a token. Requests then return `401 token_revoked`, and the app clears the Keychain item and shows the token screen.
- **Shared test vectors** in `/shared/test-vectors/signing.json` are used by both the Swift and TypeScript tests.
**Update (2026-10-12):** the token gates server features only. Onboarding, Today and manual logging work without one; the token screen can always be skipped (remembered), and a token can be added later.
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
**→ Superseded by ADR-020 (no server caps).**
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
**→ Amended by ADR-020: no Meta token; Instagram import is best effort with a screenshot fallback.**
**Status:** Accepted (2026-10-11).
- **Build machine:** Windows + GitHub Actions; a Mac only later, optionally (ADR-012).
- **Instagram import:** official oEmbed with a Meta app token; screenshot import is the fallback UX when a link can't be read.
- **Water target:** follows §6 exactly (weight + activity, no height).
- **Explore votes:** the client shows the vote button only after logging the dish; the server enforces one vote per device per dish.
- **Recipe language:** titles and ingredient names in both languages; steps in the language active at import.

### ADR-019 — Swift 5 language mode; CI compile-first, lint non-blocking
**Status:** Accepted (2026-10-13).
**Context:** Swift 6 strict concurrency produced most CI failures and adds nothing a single-user app needs. SwiftLint failures stopped the pipeline before compilation, which hid compiler errors.
**Decision:**
- **Language mode:** the app, extensions and LakhasKit build in Swift 5 language mode (`SWIFT_VERSION: 5.0`, `swiftLanguageModes: [.v5]`) with minimal concurrency checking. The Swift 6 compiler and toolchain are unchanged.
- **CI order:**
  1. a fast **compile-only** job (`xcodebuild build-for-testing -continue-building-after-errors`), which lists every compiler error and uploads the full log as an artifact;
  2. tests;
  3. unsigned IPAs.
- **SwiftLint** runs as a separate, non-blocking job.
- **Reading failures:** Claude reads them with `gh run view --log-failed` and fixes all errors from a run in one commit.

### ADR-020 — Bring Your Own Key: AI runs on the device, no server
**Status:** Accepted (2026-10-13), with these changes from the approval:
- **No certificate pinning** (open question 1).
- **No AI illustrations.** A dish or product shows the user's own photo when one was taken (stored only on the device), otherwise a styled placeholder (open question 2).
- **"High accuracy" toggle** in Settings → AI: photo analysis uses the provider's stronger model (e.g. Claude Sonnet 5.5), while text entry stays on the cheaper default.
- **All data stays on this device:** no cloud sync, and the store and photos are excluded from iCloud/iTunes device backups. The only way data leaves the phone is a backup file the user exports on purpose.
- Open questions 3–5 accepted as proposed.
**Context:** The user wants zero operating cost and no developer key, ever. Each user pays their own AI provider directly.
**Decision:**
- **AI calls:**
  - The app calls the AI provider **directly from the device** using the user's own API key. Providers: Anthropic Claude, OpenAI, Google Gemini, OpenRouter.
  - **No server**, no proxy, no developer key, and no fallback of any kind. Without a key, AI features show a "get a key" screen.
- **Settings → AI:**
  - The user picks a provider, then a model from a list (fetched from the provider's models endpoint when a key is set, otherwise a short built-in list) or types a custom model ID.
  - The user enters an API key and can tap **Test connection**. Each provider has a recommended default model for food photos.
  - Keys live only in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no iCloud, no backup). They are never logged and never sent anywhere except the chosen provider.
- **Provider abstraction in LakhasKit:**
  - One protocol, `AIProvider`, handles vision + text requests that return a JSON object for a given schema.
  - Each provider is implemented with plain `URLSession` (no third-party SDKs). Each uses its native structured-output feature where available:
    - Anthropic `output_config.format`;
    - OpenAI `response_format: json_schema`;
    - Gemini `responseSchema`;
    - OpenRouter `response_format`, where the model supports it.
  - Every response is decoded with `Codable` and validated. On invalid JSON there's one retry with the decode error appended, then a clean error.
  - **Prompts move into the app** as versioned resources. User-supplied text stays wrapped as data.
- **Data that was server-side moves into the app bundle:**
  - the food DB (USDA subset + Arabic dishes, SQLite);
  - the Explore dishes (JSON);
  - the exercise library (JSON + images).
- **Barcode** lookups go directly to Open Food Facts. Products the user contributes are stored **locally only**; there's no shared review queue.
- **Recipe link import** fetches the public page on the device:
  - **YouTube:** oEmbed + page metadata (`og:description`).
  - **TikTok:** public oEmbed.
  - **Instagram:** best effort from page metadata. It's usually login-walled, so the app falls back to screenshot import.
- **Server quotas are replaced** by an optional **local daily usage counter**, and each request shows an **estimated cost**. Token usage comes from the provider response, multiplied by a bundled, editable price table (prices are marked as estimates).
- **Removed from the plan:**
  - the Cloudflare deployment, device tokens and HMAC signing;
  - the admin panel and server quotas;
  - the token screen, Explore voting and the shared product review.
- **Kept:** EXIF stripping and downscaling before upload, Data Protection, the Keychain for secrets, no analytics, ATS (HTTPS only).
- **Backend code:** stays in `/backend` and `/shared` but is **frozen**. Its CI workflow becomes manual-only, and nothing in the app references it.

**Supersedes:**
- ADR-003 (server config table → local settings);
- ADR-004 (D1 caps → local counter);
- ADR-007 (admin panel);
- ADR-008 (server SVG rasterization, see open question 2);
- ADR-013 (device tokens + HMAC);
- ADR-015 (server cost caps).

**Amends:**
- ADR-002: structured outputs now run per provider, in the app;
- ADR-005: pinning, see open question 1;
- ADR-009: the bundled DB becomes the *only* DB;
- ADR-018: Instagram oEmbed with a Meta token is dropped.

**Consequences:**
- Running cost is zero.
- Quality and price depend on the model each user chooses.
- A user's photos and text go to the provider they picked, which the privacy notes must say.
- Without a key, the app still works for manual logging, the plate-builder, Explore, workouts, water and weight.
**Open questions (answer before Phase 4):**
1. **Certificate pinning.** Our pins only made sense for our own server. Pinning four third-party AI endpoints is fragile: they change CAs without notice, and a stale pin breaks AI until a new IPA is installed. **Proposed:** drop custom pinning and rely on ATS + system trust. Delete `CertificatePinning.swift`, its tests and the Info.plist pins.
2. **Illustrations.** Generating SVGs with the user's key costs them money, and rendering SVG on iOS needs an offscreen web view. **Proposed:** no AI illustrations, use a styled placeholder (dish-category symbol on a tinted plate). Revisit later if wanted.
3. **OpenRouter structured output** depends on the underlying model. **Proposed:** request `response_format: json_schema`. If the model rejects it, fall back to "JSON only" prompting plus `Codable` validation and the one retry. Settings marks models with weak JSON support.
4. **Price table.** Prices change. **Proposed:** a bundled table (per model, input/output per million tokens), user-editable per model, shown as "estimate", and updated with app releases. Unknown models show token counts without a cost.
5. **Contributed products** stay on this device only; there's no sharing between users. **OK?**

### ADR-021 — Bundled food DB as JSON with in-memory search
**Status:** Accepted (2026-10-13). Amends ADR-009 (SQLite + FTS5).
**Context:** The bundled DB holds about 300 foods (89 KB): a USDA SR Legacy subset with real values, plus a hand-curated table of Egyptian and Arab dishes. SQLite/FTS5 would add a build step and C-API code for no measurable gain at this size.
**Decision:**
- **Format:** `LakhasKit/Resources/FoodDB/foods.json`, loaded once into memory.
- **Search:** normalized Arabic (diacritics and tatweel removed; أ/إ/آ → ا, ى → ي, ة → ه, ؤ → و, ئ → ي) and lowercased Latin text, with tolerant spelling ("كشرى" finds "كشري", "taameya" finds "طعمية"). Results are scored exact > prefix > word-prefix > contains, over names and aliases.
- **Sources:** `ios/data/scripts/build-usda-subset.mjs` (USDA CSV → subset) and `build-food-db.mjs` (merge + validation) regenerate the file.
- **Curated dishes:** protein, carbs and fat per 100 g as served, marked `curated_estimate`. kcal is computed from them (4/4/9) so every entry is internally consistent, and each dish carries common Egyptian portions (plate, sandwich, piece, loaf, cup).
**Revisit if:** the DB grows past a few thousand entries.

### ADR-022 — Barcode: Open Food Facts from the phone, local product library, AI label reading
**Status:** Accepted (2026-10-14). Implements ADR-020 for §4.3 C.
**Decision:**
- **Lookup order:** the local `Product` library, then Open Food Facts (`world.openfoodfacts.org/api/v2/product/{code}?fields=…`, no key, an app User-Agent, 15 s timeout). Nothing else is called.
- **Barcodes** are stored in one canonical form: UPC-A becomes EAN-13 with a leading 0, GTIN-14 with a leading 0 becomes EAN-13, and EAN-13 check digits are verified. Eastern Arabic digits are accepted when typed.
- **Open Food Facts values** are used only when plausible (kcal 0–900, macros 0–100, sum ≤ 100 g per 100 g). kcal falls back to kJ ÷ 4.184, then 4/4/9 from the macros. A product with no usable values is treated like a missing one, but its name pre-fills the form.
- **Missing products:** two photos (nutrition table + front), downscaled with metadata stripped, go to the user's provider with the **standard** model (`AIFeature.label`, prompt `label.v1`). The answer is validated and fills an editable form; nothing is saved until the user taps Save. Without a key the same form is typed in by hand.
- **Library:** a product is saved locally when the user logs it (Open Food Facts results included, so the next scan works offline) or saves the form. The front photo is kept as a protected, backup-excluded thumbnail. Products are never shared (ADR-020 question 5).
- **Drinks:** values per 100 ml are treated as per 100 g (the form says so).
- **Attribution:** the barcode screen and Settings → About credit Open Food Facts under the ODbL.
- **UI tests:** `-uiTesting` answers lookups from a fixed table (`UITestingAIProvider.products`) and never reaches the network.

### ADR-023 — "Last AI request" diagnostics; Gemini request hardening
**Status:** Accepted (2026-10-15).
**Context:** Photo and text analysis failed on a real phone with a valid Gemini key, and the app only showed a generic message. There was no way to see what the provider actually said.
**Decision:**
- **Diagnostics:**
  - Every structured request leaves one `AIDiagnostic`: provider, model, feature, endpoint (no query), HTTP status, the step that failed (`network`, `http`, `response` envelope, `json`, `validation`), attempts (2 = retried), duration, the provider's message, the redacted error body, and the start of an unusable reply.
  - `AIHTTP.send` reports through a task-local `AITrace`, so providers didn't change.
  - Keys are removed (the stored key, plus `AIza…`, `sk-…` and `key=` patterns) before anything is stored. Only the last request is kept, in UserDefaults on this device.
  - **Settings → AI → Last AI request** shows it with **Copy details**. Error messages under every AI action add the HTTP status and the provider's own message, with a link to the details.
- **Gemini:**
  - Native `responseSchema`, converted to Google's OpenAPI subset (`nullable: true` instead of `["x","null"]`, `additionalProperties`/`$ref` dropped). If Gemini rejects the schema, the existing fallback resends with the schema in the prompt.
  - Thinking set low (`thinkingLevel: low`; `thinkingBudget: 1024` on 2.5; none on 1.x/2.0, flash-lite and non-thinking models). A 400 that mentions thinking is resent once without it.
  - `maxOutputTokens` = requested + 24,576 on thinking models, since thoughts count against it. `finishReason: MAX_TOKENS` is reported as truncated (partial JSON is never parsed). Thought parts are ignored. More block reasons map to "refused".
  - Requests time out after 180 s (non-streamed photo replies from thinking models can be slow).
  - Settings → AI warns when the chosen model ID isn't in the key's live model list. `gemini-flash-latest` / `gemini-pro-latest` stay the defaults: both are Google aliases, but which models a key can use depends on its tier.

### ADR-024 — Hard deadlines on AI calls; key hygiene
**Status:** Accepted (2026-10-15). Amends ADR-023.
**Context:** On a phone with a valid Google "AQ." key, Settings → AI → "Save and test" spun for 10+ minutes. Each Gemini request could wait up to 180 s, and one test may send up to four (a resend without thinking, a fallback without the schema), so a server that holds the connection open kept the spinner going for minutes.
**Decision:**
- **Deadlines:** every AI call runs under `AIDeadline`: 30 s for Test connection and the model list, 200 s for analysis. The operation runs in its own task, so even an await that never returns can't block the caller. On timeout or cancellation it's cancelled and abandoned, and a late result can't overwrite the timeout's diagnostic.
- **UI:** Test connection has a **Cancel** button. Every outcome (answer, error, timeout, cancel) stops the spinner and is recorded in Last AI request (`timeout` / `cancelled` steps).
- **Gemini auth:** the key goes only in `x-goog-api-key`, for generate and the model list. No `?key=` and no `Authorization` header (Google rejects two credentials). "AIza" and "AQ." keys are both accepted.
- **Keys:** pasted keys are sanitized on save and on read. Whitespace, line breaks, invisible format characters (zero-width, LRM/RLM, bidi isolates, BOM), wrapping quotes and a "Bearer " prefix are removed. The field is LTR with no autocorrect. A masked preview shows the first 4 and last 4 characters and the length.
- **Warnings, never blocking:** a key in another provider's format (e.g. "sk-ant-" in the Gemini field), an unknown format, leftover non-ASCII characters, or an unusually short key.

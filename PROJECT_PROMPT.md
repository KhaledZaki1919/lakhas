# Project Brief for Claude Code — AI Calorie & Macro Tracker (iOS)

> **App name:** لخّص (display name on the home screen: `لخّص`; Latin name for code and repos: **Lakhas**)
> **App languages:** Arabic (default, RTL) and English (LTR) — exactly these two. All UI text, notifications, widgets, errors and AI responses shown to the user follow the selected language.
> **Distribution:** personal use only. The app is **sideloaded** with Sideloadly from Windows using a **free Apple ID**. No App Store, no TestFlight, no Apple Developer Program (for now). See `docs/sideloading.md`.
>
> | Identifier | Value |
> |---|---|
> | Bundle ID (app) | `com.khaled.lakhas` (the signer may rewrite it; never hardcode it at runtime) |
> | Widget extension | `com.khaled.lakhas.widgets` (optional, build flag `LAKHAS_EXTENSIONS`) |
> | Share extension | `com.khaled.lakhas.share` (optional, same flag) |
> | App Group | `group.com.khaled.lakhas` (the signer may rewrite it; resolved at runtime, ADR-014) |
> | Keychain | default access group of the app only; no Keychain sharing |
> | Xcode targets / Swift modules | `Lakhas`, `LakhasWidgets`, `LakhasShare`, `LakhasKit` (shared package) |
> | Backend Worker name | `lakhas-api` |

You are the lead engineer on a new iOS app. Read this whole file before writing any code. Work in the phases listed at the end, commit after each meaningful step, and stop at the end of each phase to report what was built, what was tested, and what's next. If anything here is ambiguous or contradictory, ask before building on it.

---

## 1. Product summary

**لخّص (Lakhas)** is a bilingual Arabic/English calorie and macro tracker, Arabic by default. The user photographs a plate, types what they ate, or scans a barcode; AI identifies the foods, estimates grams, and logs calories, protein, carbs and fat into their day. Around that core: recipes imported from social-media links or screenshots, a curated "Explore" dish library, a gym workout program and log, water tracking, weight/progress tracking, widgets and reminders.

It is a **personal app**: no user accounts, no payments, every feature enabled for everyone. Each device is authorized with an **access token** issued from the admin panel. AI spending is limited by configurable **per-device daily cost caps**.

Target user: Arabic speakers, with strong recognition of Arabic and Egyptian/Gulf dishes (koshary, foul, ta'ameya, mahshi, molokhia, fattah, kabsa, mandi, etc.) by their Arabic names.

**Original product, not a clone.** All naming, branding, icons, copy, screen layouts and visual design must be our own original work. Do not copy text, assets, datasets or layouts from any existing app.

---

## 2. Tech stack (decided — don't change without asking)

### iOS app
- **Swift 6 + SwiftUI**, minimum **iOS 17** (needed for SwiftData and interactive widgets).
- **XcodeGen** (`project.yml`) to generate the Xcode project — never hand-edit `.pbxproj`.
- **SwiftData** for all local data. The store lives in the **App Group** container when one is available at runtime, otherwise in the app's own container (ADR-014).
- **WidgetKit** + **AppIntents** (interactive widgets) and the **share extension** are compiled only when the `LAKHAS_EXTENSIONS` build flag is on. The app must be fully usable without them.
- **VisionKit `DataScannerViewController`** for barcodes; **AVFoundation / PhotosPicker** for camera and library.
- **UserNotifications** for **local** reminders only. No push notifications.
- No third-party UI libraries. Swift Package Manager only, and only when clearly justified.
- Languages: **Arabic + English only** (development region `ar`).
  - All user-facing strings live in a String Catalog (`.xcstrings`) with both translations complete — no hardcoded literals in views, no missing keys (add a test or build check that fails on untranslated strings).
  - The app follows the device language by default, with an in-app language switcher in Settings that changes language and layout direction (RTL ↔ LTR) without reinstalling.
  - Arabic copy: Modern Standard Arabic with a light, friendly tone that Egyptian users find natural. English copy: plain and friendly.
  - In Arabic, use Western digits (0–9) by default for numbers, grams and calories, with an option for Eastern Arabic digits (٠–٩) in Settings.
- **AI output language:** every backend AI request includes the app's current language (`ar` | `en`). Claude returns food names, recipe titles, steps and messages in that language. Store both Arabic and English names for foods so a log made in one language displays correctly after switching.

### Build & distribution (ADR-012)
- Development happens on **Windows**. All iOS builds run on **GitHub Actions macOS runners**.
- On every push to `main`, CI:
  1. generates the project with XcodeGen;
  2. builds and runs the unit tests on the iOS Simulator;
  3. builds an **unsigned** `.ipa` (`CODE_SIGNING_ALLOWED=NO`), embeds the entitlements with an ad-hoc signature (`codesign --sign -`, no certificate, no secret) so the sideloading tool can read them, zips `Payload/Lakhas.app`, and uploads it as a workflow artifact.
  4. It does this for two variants: **Lakhas-full** (with extensions) and **Lakhas-lite** (app only).
- No signing secrets, no TestFlight workflow, no App Store Connect.
- The user downloads the artifact and installs it with **Sideloadly** using a free Apple ID. Free-account apps expire after 7 days and must be refreshed (Sideloadly can auto-refresh).
- A Mac is optional, later, only for faster UI iteration.

### Backend
- **Cloudflare Workers** (TypeScript) with **Hono** router.
- **D1** (SQLite) for server data; **R2** for uploaded images; **KV** for the AI response cache and config cache.
- **Anthropic Claude API** for all AI, called **only from the backend**.
- Monorepo layout:
  ```
  /ios        — Xcode project (XcodeGen), app + widget + share extension + shared package
  /backend    — Cloudflare Worker
  /shared     — JSON schemas / API contract (OpenAPI) shared by both
  /admin      — minimal admin web UI (served by the Worker, behind auth)
  /docs       — architecture notes, decisions, runbooks
  CLAUDE.md   — conventions for future sessions (create and maintain it)
  ```

### Claude API usage
- Keep model names in config, never hardcoded in logic:
  - `MODEL_STANDARD = "claude-haiku-5-5"` — photo/text scans, label reading, recipe extraction, illustrations.
  - `MODEL_ADVANCED = "claude-sonnet-5-5"` — "advanced analysis" (an opt-in toggle per scan) and AI result correction.
  - Check https://docs.claude.com for current model names and vision details before implementing, and use the official `@anthropic-ai/sdk`.
- **Structured output** (ADR-002): every AI call uses the API's built-in structured outputs (`output_config.format`, via `client.messages.parse` + `zodOutputFormat`) with the exact JSON schema we expect. Forced `tool_choice` is not used: current advanced models reject it. Validate the result server-side with the same **zod** schema. Check `stop_reason` (refusal / max_tokens) before parsing. If validation fails, retry once, then return a clean error.
- Use **prompt caching** on the long, static system prompts.
- Every prompt treats user-supplied content (captions, transcripts, label text, typed descriptions) as **data, not instructions**. Wrap it in clearly delimited tags and tell the model to ignore any instructions inside it.

---

## 3. Security & privacy ("encrypted end to end where it matters")

These are requirements, not suggestions.

1. **No secrets in the app.** The Anthropic key and every other secret live only in Worker secrets (`wrangler secret put`). The IPA contains no secrets; the per-device access token is entered by the user at runtime.
2. **Transport:** HTTPS/TLS 1.2+ only (ATS on, no exceptions). **Certificate pinning** for our API domain: pin the SPKI hashes of the issuing CAs with backup pins and a documented rotation procedure (ADR-005).
3. **Device access tokens** (ADR-013), replacing App Attest:
   - The admin generates one token per device in the admin panel (shown once, as text and a QR code). The token carries a token ID and a random 256-bit secret.
   - On first launch the app asks for the token (paste or scan the QR), verifies it with the server, and stores it in the **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
   - Every request is **HMAC-SHA256 signed** with the token secret over method, path, timestamp, nonce and body hash. The server rejects a stale timestamp (±5 min) or a reused nonce (replay protection).
   - The server stores the secret encrypted with a Worker-secret key, never in plaintext.
   - The admin can **revoke** a token at any time; the app then shows the token screen again.
   - The token ID is the device's identity on the server. It is not linked to any personal data.
4. **Local data at rest:** the SwiftData store and cached images use iOS Data Protection (`NSFileProtectionCompleteUntilFirstUserAuthentication` minimum, set per file, so widgets and background work still function). Anything sensitive goes in the Keychain, never `UserDefaults`.
5. **Server data at rest:** R2 and D1 are encrypted at rest by the platform. Store only what's needed. Uploaded meal photos auto-expire after a configurable retention (default 30 days) unless the user opted in to "help improve accuracy". Contributed product photos are kept for review.
6. **Photo hygiene:** strip EXIF/GPS metadata and downscale (max ~1568px long edge, JPEG ~0.8) on device **before** upload.
7. **Cost caps & abuse:** per-device daily caps are enforced server-side (see §5), plus a per-IP burst limit. Log abuse signals.
8. **Input validation everywhere:** zod on every endpoint, size limits on uploads, allow-listed URL hosts for recipe import, and an SSRF-safe fetcher (no private IPs, no redirects to internal hosts, timeouts, max body size).
9. **No analytics SDKs, no ads, no tracking.** Privacy manifest (`PrivacyInfo.xcprivacy`) must be accurate.
10. **Data deletion:** in-app "Delete my data" calls a backend endpoint that wipes everything tied to the device's token, then resets local data.

---

## 4. Features (all required, all enabled for everyone)

### 4.1 First launch & onboarding
- **Access token** screen first (paste or scan QR), with **Continue without a token** always available. Onboarding, Today and manual logging work without a token; server features (AI analysis, barcode lookup, recipe import, Explore) need a verified token.
- Collect sex, age, height, weight, activity level (4 levels), goal (lose / maintain / gain) and pace (lose 0.25–1.0 kg/week, gain 0.25–0.5 kg/week).
- Show a plain-language body summary: BMI category and the healthy weight range for their height.
- Compute targets with the formula in §6.
- Ask for notification permission in context, not on first screen.

### 4.2 Today (home)
- Daily ring/counter: consumed vs target, remaining, and macro bars labeled by name (not color alone).
- The header holds the date and a **Progress** button (Progress is not a tab, see §9).
- Meals grouped into **Breakfast, Lunch, Dinner, Snack**.
  - Default by time of day; the user can change a meal's type, or long-press and drag a meal to another group.
- Swipe to re-log a meal; swipe to delete with **Undo**.
- "Log again today" from any previous day in one tap.
- Celebration animation when the daily target is reached (respect Reduce Motion).
- Date strip to browse past days.

### 4.3 Logging methods

**A. Photo scan (core)**
- Camera or library → upload → AI returns a list of items, each with:
  - Arabic and English names, estimated grams, confidence;
  - per-100g calories/protein/carbs/fat;
  - an optional `food_db_id` match.
- **Review screen** before saving:
  - edit any item's grams (tap the number to type it, or use a slider);
  - add or remove items, with live recalculation;
  - choose the meal type.
- "Correct with AI" — the user types a correction ("the rice was half that, no oil"), and the advanced model revises the result.
- **Differentiator — leftovers ("before/after"):** optional second photo of what was left on the plate. The AI estimates the uneaten portion and subtracts it. Both photos count as one scan.

**B. Text entry**
- Free-text mode: "half a grilled chicken with rice and salad" → same AI analysis and the same review screen.
- Plate-builder mode: search the food database (local first, then server), pick an item, set the amount, and repeat while totals update live. This mode uses **no AI cap**.

**C. Barcode**
- Scan → look up our D1 product table first, then the **Open Food Facts** API. Show ODbL attribution in the UI and in the About screen.
- If not found: the user takes **two photos** (nutrition table + product front).
  - The AI extracts product name, brand, serving size and per-100g values.
  - The product is saved as `pending_review` but usable immediately by the contributor.
  - After admin approval, it's visible to every device.
  - Other devices see a simple **generated illustration** (SVG, see §4.9), never the contributor's photo.

**D. Saved meals**
- Save any logged meal as a reusable "ready meal" and log it in one tap.

### 4.4 Recipes
- **Import from link:** TikTok, Instagram, YouTube (share extension when built, plus paste in-app).
  - The backend fetches **only public text**: oEmbed/meta tags/captions for TikTok and Instagram (Instagram via the official oEmbed with a Meta app token), title + description for YouTube (YouTube Data API key as a Worker secret).
  - Claude extracts title, servings, ingredients with grams, steps, and per-serving macros. Titles and ingredient names come in both languages; steps in the language active at import.
- **Import from screenshot:** image → the same extraction. Generate an illustration for the recipe (§4.9).
- Recipe detail:
  - scale servings;
  - edit ingredients and grams with live macros;
  - log one serving to today.
- **"My Recipes" hub** with tabs: imported links, saved Explore dishes, saved meals, products.
- Store the source URL and creator handle; imported recipes are for personal use.

### 4.5 Explore
- Curated dish library (managed in the admin panel): photo, macros, ingredients with measures, and a tag for goal (lose / gain / maintain).
- Filters by goal and meal type. Sorting: newest, and **most upvoted**.
- After logging an Explore dish, the user can vote 👍/👎 (one vote per device per dish, server-side; the client shows the vote button only after logging).
- Browsing and logging from Explore use no AI cap.

### 4.6 Workouts
- Program builder:
  - inputs: training days per week, available equipment (full gym / dumbbells only / machines / bodyweight), experience level;
  - generates a split (full body, upper/lower, push/pull/legs). Full body can alternate two different days (A/B).
- Exercise library seeded from an **open-licensed dataset** with images (e.g. `free-exercise-db`, public domain — verify the license before importing).
  - Each exercise has barbell / dumbbell / machine alternatives and target muscles.
- Session logging: sets × reps × weight, one-tap "repeat last set", rest timer.
- Editing the program **never deletes past logs**.
- Progress:
  - estimated 1RM / top-set trend per lift;
  - weekly sets per muscle group;
  - consistency calendar.

### 4.7 Water, weight & progress
- **Water:** the daily target follows §6 (weight + activity), editable. The main control is a vertical "fill column" the user drags up/down; amounts snap to sensible steps.
- **Weight:** log entries and show a chart (Swift Charts) with a trend line.
- **Progress screen** (opened from the Today header): weight trend, calories vs target per day, logging streak.

### 4.8 Settings & goals
- Custom calorie/macro targets ("My Goals"), overriding the computed ones, including an optional goal weight.
- Language (System / العربية / English), units (kg/lb, g/oz, ml/fl oz; metric by default), digit style in Arabic (Western/Eastern Arabic), appearance (light/dark/system).
- Reminders for meals, water and training: each individually toggleable, scheduled locally.
- **Access token:** status, replace token.
- **Backup:** export all local data to a file (share sheet / Files) and import it back (ADR-016). This protects data when the app is reinstalled or re-signed under a different identity.
- **Sideloading status:** shows whether widgets and the share extension are active in this build (ADR-014).
- Privacy notes, Open Food Facts attribution, Delete my data.

### 4.9 AI-generated illustrations
Claude does not generate raster images. For dish/product illustrations, ask Claude to produce a **simple, flat, self-contained SVG** (fixed palette, `viewBox="0 0 256 256"`, no external refs, no scripts).
- Sanitize the SVG server-side (allow-list elements and attributes), store it in R2, and rasterize it to PNG on the backend (ADR-008).
- Used for recipes and contributed products.

### 4.10 Widgets (WidgetKit, only in builds with `LAKHAS_EXTENSIONS`)
- Calories remaining (small/medium).
- Water — with a "+250 ml" button (AppIntent).
- Log a set — next exercise in today's workout with a "done" button.
- Recipes — quick open.
- This week — mini calorie bars.
- If no shared App Group container is available at runtime, widgets show "Open لخّص to set up widgets" instead of data.

---

## 5. Cost caps (per device, per local day)

Single tier. Defaults below; all values live in server config and can be changed in the admin panel without a new build.

| Cap | Default |
|---|---|
| Photo meal scans (leftover photo included) | 10 |
| Recipe imports (link or screenshot) | 5 |
| AI text entries | 5 |
| Barcode scans | 10 |
| AI corrections | 10 |
| Global per-device cap (all AI types) | 40 |
| Explore browsing & logging, plate-builder | unlimited |

**Rules (server-enforced):**
- Each type has its own counter.
- Counters reset at the start of the device's local day. The client sends its IANA timezone; the server clamps implausible timezone changes (max one change per 24h).
- **Failed requests don't count.**
- **Retries of the same input on the same day don't count.** Dedupe by SHA-256 of the normalized input (image bytes / URL / text / barcode) and return the cached result.
- A barcode lookup counts only when a product is returned.
- The admin can override caps per device (e.g. a higher cap for the owner's phone).

---

## 6. Nutrition math (exact)

- **BMR — Mifflin-St Jeor:**
  - male: `10·kg + 6.25·cm − 5·age + 5`
  - female: `10·kg + 6.25·cm − 5·age − 161`
- **TDEE** = BMR × activity factor:

  | Activity level | Factor |
  |---|---|
  | Sedentary | 1.2 |
  | Light (1–3 days/week) | 1.375 |
  | Active (3–5 days/week) | 1.55 |
  | Very active / daily training | 1.725 |

- **Goal adjustment:** ±250 kcal/day per 0.25 kg/week of target pace (lose = subtract, gain = add).
- **Floor:** never below max(BMR × 1.0, 1200 kcal for female / 1500 kcal for male). Show a gentle note when the floor applies.
- **Protein:** g/kg of body weight:

  | Goal | g/kg |
  |---|---|
  | Lose | 2.0 |
  | Maintain | 1.6 |
  | Gain | 1.8 |

  When BMI ≥ 30, use the reference weight at BMI 25 for the user's height (`25 × m²`), unless the user set a goal weight in My Goals.
- **Fat:** 27% of calories ÷ 9.
- **Carbs:** remaining calories ÷ 4 (never negative; if negative, reduce fat to a 20% minimum first).
- **Water:** `35 ml × kg`, +10% if activity ≥ active, rounded to the nearest 250 ml. User-editable.
- Put all of this in a pure, unit-tested Swift module (`NutritionMath`), with the same formulas mirrored in TypeScript tests on the backend for consistency.

---

## 7. AI accuracy architecture

Don't let the LLM be the single source of truth for macros.

1. **Food database:**
   - Seed D1 with **USDA FoodData Central** (public domain), covering the common subset. Arabic names are machine-translated at seed time and flagged for review.
   - Add a hand-curated **Arabic/Egyptian dishes table** with typical portion weights (cup, plate, loaf, piece) in both languages. Create the seed file with clearly marked estimated values and a `source` column so we can refine it later.
   - Ship a compact version of the DB in the app for offline plate-builder search.
2. **Photo/text analysis flow:**
   - Claude returns items with names, estimated grams, per-100g macros and a best-guess `food_db_id` from a candidate list we include in the prompt (top-N fuzzy matches for common dishes).
   - The server **overrides per-100g values with DB values when the match confidence is high**, keeps the model values otherwise, and marks each item's `source` (`db` | `ai`).
3. Totals are always computed by our code (grams × per-100g), never taken from the model's arithmetic.
4. Store anonymized `(predicted grams → user-corrected grams)` pairs per dish (only if the user opted in) to tune default portions later.

Write all system prompts as versioned files in `/backend/prompts/`, each with:
- the role and task;
- Arabic-food awareness;
- an explicit instruction to estimate grams from visual cues (plate size, utensils);
- the output schema;
- 2–3 few-shot examples;
- the injection-resistance instruction.

---

## 8. Backend API (define in `/shared/openapi.yaml` first)

Minimum endpoints (all JSON, all require a valid HMAC-signed device token except `/health`):

| Method & path | Purpose |
|---|---|
| `GET /health` | liveness (no auth) |
| `GET /v1/device` | verify token; returns device label, caps and server time |
| `POST /v1/analyze/photo` | multipart image (+ optional leftover image) → items |
| `POST /v1/analyze/text` | description → items |
| `POST /v1/analyze/correct` | previous result + correction text → items |
| `GET /v1/barcode/:code` | product or 404 |
| `POST /v1/products/contribute` | two images → product (pending review) |
| `POST /v1/recipes/import-link`, `POST /v1/recipes/import-image` | recipe import |
| `GET /v1/foods/search?q=&lang=` | food DB search |
| `GET /v1/explore`, `POST /v1/explore/:id/vote` | Explore library and votes |
| `GET /v1/quota` | remaining caps per type |
| `DELETE /v1/device` | delete all data for this device |
| `/admin/*` | protected by Cloudflare Access |

The admin panel covers: device tokens (create with QR, label, per-device caps, revoke, usage), Explore CRUD, contributed-product review queue, machine-translation review queue, and cap/config editing.

Generate a typed Swift API client from the OpenAPI spec (or hand-write it to match exactly), with retries and offline queueing for non-AI writes.

---

## 9. UI / design direction

- **Design system: direction A, "Tahini & Mint" (طحينة ونعناع)**, locked in `/docs/design.md`. Build every screen from its tokens.
- Layouts must work in both directions: test every screen, chart, slider, swipe action and widget in Arabic (RTL) and English (LTR). Use leading/trailing, never left/right.
- Use SF Arabic / system fonts.
- Logo and wordmark: the shadda-on-plate mark around the Arabic name **لخّص**, with a matching Latin wordmark **Lakhas**.
- Dynamic Type, VoiceOver labels on every control, sufficient contrast, Reduce Motion respected, dark mode.
- Navigation: tab bar — **Today, Recipes, [+], Explore, Workouts** — four tabs with a prominent center "+" for logging (photo / text / barcode / saved meal). **Progress** opens from the Today header.
- Haptics on log success; skeleton states while AI runs; friendly, specific error messages with a retry.

---

## 10. Quality bar

- **Unit tests:**
  - `NutritionMath`;
  - cost-cap logic (including dedupe and timezone clamping);
  - request signing (HMAC) — shared test vectors used by both the Swift and TypeScript tests;
  - token storage and revocation handling;
  - SVG sanitizer;
  - zod schemas.
- **Integration tests** for each backend endpoint using a mocked Anthropic client.
- **UI tests** for:
  - token entry + onboarding;
  - photo-log happy path (mocked backend).
- **Build verification:** CI must build the app (both variants), run the unit tests on the iOS Simulator and produce the unsigned IPAs; `wrangler deploy --dry-run` and `npm test` must pass for the backend.
- **Conventions:**
  - SwiftLint and ESLint/Prettier configured;
  - no force-unwraps in production code;
  - structured logging without PII.
- Keep `CLAUDE.md` updated with build commands, conventions and architecture decisions.
- Keep `/docs/decisions.md` (short ADRs).

---

## 11. Phases (stop and report after each)

| Phase | Scope |
|---|---|
| **0 — Plan** ✅ | `/docs/architecture.md`, `/docs/design.md`, ADRs, sideloading findings. |
| **1 — Skeleton** | Monorepo, XcodeGen project (app + optional widget/share extensions behind `LAKHAS_EXTENSIONS`, shared package), Worker with Hono + D1/R2/KV bindings, OpenAPI spec, GitHub Actions (unit tests + unsigned IPA artifacts for both variants, backend CI), `CLAUDE.md`, and a **capability probe** screen to verify App Group / widget / Keychain behavior on the sideloaded device. |
| **2 — Security foundation** | Device tokens (minimal admin create/revoke), HMAC signing end-to-end with replay protection, certificate pinning, data protection, rate limiter + cost caps with dedupe. |
| **3 — Onboarding + NutritionMath + Today screen** | Local data only. |
| **4 — Photo & text analysis** | Claude integration, food DB seed, review screen, correction, leftovers. |
| **5 — Barcode + product contribution + SVG illustrations** | |
| **6 — Recipes** | Link import, screenshot import, share extension, My Recipes hub. |
| **7 — Explore + voting + admin panel** | |
| **8 — Workouts** | Exercise DB, program builder, logging, progress. |
| **9 — Water, weight, progress, widgets, reminders** | |
| **10 — Settings, backup export/import, delete-my-data, privacy manifest, Arabic & English copy review** | Review all copy in both languages for consistency, tone and completeness. Run the full app in each language. |
| **11 — Hardening** | Full test pass, accessibility audit, sideloading runbook, refresh/backup drill. |

**Later / optional:**
- iCloud (CloudKit) sync — needs the paid Apple Developer Program.
- Apple Health integration.
- App Store release (would bring back StoreKit, App Attest, push, TestFlight).
- Android.

---

## 12. Things I will provide when you ask

- Anthropic API key (as a Worker secret — never paste it into code or chat logs).
- Cloudflare account and domain for the API.
- YouTube Data API key.
- Meta app access token for Instagram oEmbed.
- A GitHub repository for the monorepo and CI.

Phase 0 is complete. Continue with **Phase 1**.

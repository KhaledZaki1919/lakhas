# Project Brief for Claude Code — AI Calorie & Macro Tracker (iOS)

> **Revision 3 — Bring Your Own Key (ADR-020), pending approval.** The app has no server. AI runs on the device against the provider the user picks, with the user's own API key.
>
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

You are the lead engineer on a new iOS app. Read this whole file before writing any code. Work in the phases listed at the end, commit after each meaningful step, and stop at the end of each phase to report what was built, what was tested, and what's next. If anything here is ambiguous or contradictory, ask before building on it.

---

## 1. Product summary

**لخّص (Lakhas)** is a bilingual Arabic/English calorie and macro tracker, Arabic by default. The user photographs a plate, types what they ate, or scans a barcode; AI identifies the foods, estimates grams, and logs calories, protein, carbs and fat into their day. Around that core: recipes imported from social-media links or screenshots, a curated "Explore" dish library, a gym workout program and log, water tracking, weight/progress tracking, widgets and reminders.

It is a **personal app with no server**:
- no accounts, no payments, every feature enabled;
- **Bring Your Own Key** (ADR-020): each user enters their own API key for Anthropic Claude, OpenAI, Google Gemini or OpenRouter, and pays that provider directly. There is no developer key and no fallback to any server.
- Without a key the app still works for manual logging, the plate-builder (bundled food DB), Explore, barcode lookup on Open Food Facts, workouts, water and weight.

Target user: Arabic speakers, with strong recognition of Arabic and Egyptian/Gulf dishes (koshary, foul, ta'ameya, mahshi, molokhia, fattah, kabsa, mandi, etc.) by their Arabic names.

**Original product, not a clone.** All naming, branding, icons, copy, screen layouts and visual design must be our own original work. Do not copy text, assets, datasets or layouts from any existing app.

---

## 2. Tech stack (decided — don't change without asking)

### iOS app
- **Swift 5 language mode** (Swift 6 toolchain, minimal concurrency checking, ADR-019) + **SwiftUI**, minimum **iOS 17**.
- **XcodeGen** (`project.yml`) to generate the Xcode project — never hand-edit `.pbxproj`.
- **SwiftData** for all user data. The store lives in the **App Group** container when one is available at runtime, otherwise in the app's own container (ADR-014).
- **Bundled reference data** (read-only):
  - the food DB (SQLite, FTS5);
  - Explore dishes (JSON + images);
  - the exercise library (JSON + images).
- **WidgetKit** + **AppIntents** and the **share extension** are compiled only when the `LAKHAS_EXTENSIONS` build flag is on. The app must be fully usable without them.
- **VisionKit `DataScannerViewController`** for barcodes; **AVFoundation / PhotosPicker** for camera and library.
- **UserNotifications** for **local** reminders only. No push notifications.
- No third-party UI libraries, no AI SDKs: providers are called with `URLSession`. Swift Package Manager only, and only when clearly justified.
- Languages: **Arabic + English only** (development region `ar`).
  - All user-facing strings live in a String Catalog (`.xcstrings`) with both translations complete — no hardcoded literals in views, no missing keys (CI check).
  - The app follows the device language by default, with an in-app language switcher in Settings that changes language and layout direction (RTL ↔ LTR) without reinstalling.
  - Arabic copy: Modern Standard Arabic with a light, friendly tone that Egyptian users find natural. English copy: plain and friendly.
  - In Arabic, use Western digits (0–9) by default for numbers, grams and calories, with an option for Eastern Arabic digits (٠–٩) in Settings.
- **AI output language:** every AI request includes the app's current language (`ar` | `en`). The model returns food names, recipe titles, steps and messages in that language. Store both Arabic and English names for foods so a log made in one language displays correctly after switching.

### AI providers (ADR-020)
- **Providers:** Anthropic Claude, OpenAI, Google Gemini, OpenRouter. The user picks one in **Settings → AI**.
- **Model:** chosen from a list or typed as a custom model ID. When a key is set, the list is fetched from the provider's models endpoint; otherwise a short built-in list is shown. Each provider has a **recommended default for food photos**, chosen at implementation time from the provider's current docs.
  - For Anthropic: `claude-haiku-5-5` as the fast, cheap default, and `claude-sonnet-5-5` as "more accurate".
- **API key:** entered by the user and stored only in the Keychain (`WhenUnlockedThisDeviceOnly`). It's never logged and never sent anywhere except the chosen provider. **Test connection** sends a minimal request and reports success or a specific error (invalid key, no credit, model not found, network).
- **One abstraction in LakhasKit:** `AIProvider` handles vision + text requests that return JSON for a given schema. Each provider uses its native structured-output feature where available:
  - Anthropic `output_config.format`;
  - OpenAI `response_format: json_schema`;
  - Gemini `responseSchema`;
  - OpenRouter `response_format`, where the model supports it.
  Every response is decoded with `Codable` and validated (ranges, required fields). On invalid JSON there's **one retry** with the error appended, then a clean, localized error.
- **Prompts live in the app** as versioned resources (`LakhasKit/Resources/Prompts/*.v1.md`). User-supplied text (captions, label text, typed descriptions) is wrapped in delimited tags as **data, not instructions**.
- **No key set:** AI entry points open a friendly screen. It explains what a key is, how to get one for each provider (with links), what it roughly costs, and where to enter it. There is no fallback.

### Build & distribution (ADR-012)
- Development happens on **Windows**. All iOS builds run on **GitHub Actions macOS runners**.
- **CI on every push** (ADR-019):
  1. a compile-only job (full build log as an artifact);
  2. unit and UI tests on the Simulator;
  3. **unsigned** IPAs (**Lakhas-full** with extensions, **Lakhas-lite** without), with entitlements embedded by an ad-hoc signature.
  SwiftLint runs as a separate, non-blocking job.
- No signing secrets, no TestFlight, no App Store Connect. The user installs with **Sideloadly** (free Apple ID, 7-day refresh).

### Repository layout
```
/ios        — Xcode project (XcodeGen), app + widget + share extension + LakhasKit package
/backend    — FROZEN (ADR-020): former Cloudflare Worker, kept for reference, not built or deployed
/shared     — test vectors (nutrition); FROZEN: openapi.yaml, signing vectors
/admin      — FROZEN
/docs       — architecture notes, decisions, runbooks
CLAUDE.md   — conventions for future sessions
```

---

## 3. Security & privacy

These are requirements, not suggestions.

1. **No secrets in the app binary.** The IPA contains no keys. The user's provider key is entered at runtime and stored only in the **Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: not synced, not in backups). It's shown masked, and the user can delete it.
2. **Transport:** HTTPS/TLS 1.2+ only (ATS on, no exceptions). Requests go only to the chosen AI provider, Open Food Facts, and the public recipe page the user shares. (Certificate pinning: see open question 1 in ADR-020.)
3. **Where data goes:** photos and text sent for analysis go **directly to the provider the user picked**, under that provider's terms. Settings → AI and the privacy notes say so plainly.
4. **Local data at rest:** the SwiftData store and cached images use iOS Data Protection (`NSFileProtectionCompleteUntilFirstUserAuthentication` minimum, set per file, so widgets and background work still function). Anything sensitive goes in the Keychain, never `UserDefaults`.
5. **Photo hygiene:** strip EXIF/GPS metadata and downscale (max ~1568px long edge, JPEG ~0.8) on device **before** any upload.
6. **Untrusted input:**
   - AI responses are validated before use.
   - Recipe pages are fetched with a safe fetcher: allow-listed hosts (tiktok.com, instagram.com, youtube.com, youtu.be), HTTPS only, timeouts, a max body size, and redirects re-checked against the allow-list.
   - Page text and captions are passed to the model as data.
7. **No analytics SDKs, no ads, no tracking.** The privacy manifest (`PrivacyInfo.xcprivacy`) must be accurate.
8. **Delete my data:** wipes the local store, the cached images and the stored API key. There is nothing on any server to delete.

---

## 4. Features (all required, all enabled for everyone)

### 4.1 First launch & onboarding
- Collect sex, age, height, weight, activity level (4 levels), goal (lose / maintain / gain) and pace (lose 0.25–1.0 kg/week, gain 0.25–0.5 kg/week).
- Show a plain-language body summary: BMI category and the healthy weight range for their height.
- Compute targets with the formula in §6.
- Optional last step: **"Set up AI"** (provider + key), skippable. It can be done later in Settings → AI.
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

**A. Photo scan (core, needs a key)**
- Camera or library → downscale + strip metadata → the provider returns a list of items, each with:
  - Arabic and English names, estimated grams, confidence;
  - per-100g calories/protein/carbs/fat;
  - an optional `food_db_id` match from the bundled DB.
- **Review screen** before saving:
  - edit any item's grams (tap the number to type it, or use a slider);
  - add or remove items, with live recalculation;
  - choose the meal type.
- "Correct with AI": the user types a correction ("the rice was half that, no oil") and the model revises the result.
- **Differentiator — leftovers ("before/after"):** optional second photo of what was left on the plate. The AI estimates the uneaten portion and subtracts it.
- Each AI result shows its **estimated cost**.

**B. Text entry**
- Free-text mode (needs a key): "half a grilled chicken with rice and salad" → same analysis, same review screen.
- Plate-builder mode (no key): search the **bundled food DB**, pick an item, set the amount, and repeat while totals update live.

**C. Barcode (no key for lookup)**
- Scan → look up the user's local products first, then **Open Food Facts** directly. Show ODbL attribution in the UI and in the About screen.
- If not found (needs a key): the user takes **two photos** (nutrition table + product front). The AI extracts product name, brand, serving size and per-100g values, and the product is saved **locally** for this user.

**D. Saved meals**
- Save any logged meal as a reusable "ready meal" and log it in one tap.

### 4.4 Recipes
- **Import from link** (share extension when built, plus paste in-app). The app fetches the **public page** on the device:
  - **YouTube:** oEmbed + page metadata (title, `og:description`).
  - **TikTok:** public oEmbed (caption).
  - **Instagram:** page metadata, best effort. It's usually login-walled, so when nothing useful comes back the app suggests a screenshot import.
  - The model (needs a key) extracts title, servings, ingredients with grams, steps, and per-serving macros. Titles and ingredient names come in both languages; steps in the language active at import.
- **Import from screenshot:** image → the same extraction.
- Recipe detail:
  - scale servings;
  - edit ingredients and grams with live macros;
  - log one serving to today.
- **"My Recipes" hub** with tabs: imported links, saved Explore dishes, saved meals, products.
- Store the source URL and creator handle; imported recipes are for personal use.

### 4.5 Explore (bundled, no key)
- Curated dish library shipped inside the app: photo, macros, ingredients with measures, and a goal tag (lose / gain / maintain). It's updated with app releases.
- Filters by goal and meal type. Sort: newest and A–Z.
- **Favorites** (local) replace server votes.

### 4.6 Workouts
- Program builder:
  - inputs: training days per week, available equipment (full gym / dumbbells only / machines / bodyweight), experience level;
  - generates a split (full body, upper/lower, push/pull/legs). Full body can alternate two different days (A/B).
- Exercise library bundled from an **open-licensed dataset** with images (e.g. `free-exercise-db`, public domain — verify the license before importing).
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
- **AI:**
  - provider and model (list, or a custom ID);
  - API key (masked; replace/delete) and **Test connection**;
  - recommended model per provider;
  - **usage today/this month**: number of requests and estimated cost;
  - an optional **daily usage limit** (local, off by default).
- Custom calorie/macro targets ("My Goals"), overriding the computed ones, including an optional goal weight.
- Language (System / العربية / English), units (kg/lb, g/oz, ml/fl oz; metric by default), digit style in Arabic (Western/Eastern Arabic), appearance (light/dark/system).
- Reminders for meals, water and training: each individually toggleable, scheduled locally.
- **Backup:** export all local data to a file (share sheet / Files) and import it back (ADR-016). The API key is never included.
- **Sideloading status:** shows whether widgets and the share extension are active in this build (ADR-014).
- Privacy notes (including where AI requests go), Open Food Facts attribution, Delete my data.

### 4.9 Illustrations
See ADR-020 open question 2. Proposed: no AI-generated illustrations. Recipes and products without a photo show a styled placeholder (dish-category symbol on a tinted plate).

### 4.10 Widgets (WidgetKit, only in builds with `LAKHAS_EXTENSIONS`)
- Calories remaining (small/medium).
- Water — with a "+250 ml" button (AppIntent).
- Log a set — next exercise in today's workout with a "done" button.
- Recipes — quick open.
- This week — mini calorie bars.
- If no shared App Group container is available at runtime, widgets show "Open لخّص to set up widgets" instead of data.

---

## 5. Usage & cost (local, optional)

- **Recording:** every AI request records provider, model, input/output tokens (from the provider's response) and an **estimated cost**. The cost uses a bundled, editable price table per model, labeled "estimate".
- **Settings → AI** shows requests and estimated cost for today and this month.
- **Optional daily limit**, set by the user (off by default): a number of AI requests per day. When reached, AI features pause until tomorrow, and the user can override.
- **Same input, same day:** a retry of the same input on the same day (SHA-256 of the normalized image/text/URL) reuses the cached result instead of paying again.
- **Failures:** failed requests are recorded as failed, with no cost estimate unless the provider reported usage.

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
- Implemented in the pure, unit-tested Swift module `NutritionMath`, tested against `shared/test-vectors/nutrition.json`.

---

## 7. AI accuracy architecture

Don't let the LLM be the single source of truth for macros.

1. **Bundled food database** (SQLite with FTS5, in the app):
   - the common subset of **USDA FoodData Central** (public domain), with Arabic names machine-translated at build time and flagged;
   - a hand-curated **Arabic/Egyptian dishes table** with typical portion weights (cup, plate, loaf, piece) in both languages, clearly marked estimated values, and a `source` column.
2. **Photo/text analysis flow:**
   - The model returns items with names, estimated grams, per-100g macros and a best-guess `food_db_id` from a candidate list included in the prompt (top-N local fuzzy matches).
   - The app **overrides per-100g values with DB values when the match confidence is high**, keeps the model values otherwise, and marks each item's `source` (`db` | `ai`).
3. Totals are always computed by our code (grams × per-100g), never taken from the model's arithmetic.
4. Corrections the user makes (predicted → corrected grams per dish) are kept locally to improve default portions on this device.

Prompts are versioned app resources, each with:
- the role and task;
- Arabic-food awareness;
- an explicit instruction to estimate grams from visual cues (plate size, utensils);
- the output schema;
- 2–3 few-shot examples;
- the injection-resistance instruction.

They're written to work across all four providers.

---

## 8. External services (called directly from the device)

| Service | Used for | Key |
|---|---|---|
| Anthropic / OpenAI / Google Gemini / OpenRouter | photo, text, label and recipe analysis; correction | user's own |
| Open Food Facts API | barcode lookup | none |
| TikTok oEmbed, YouTube oEmbed, public page metadata | recipe link import | none |

There is no backend. `/backend`, `/shared/openapi.yaml` and `/admin` are frozen for reference (ADR-020).

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
  - `NutritionMath` (shared vectors);
  - each AI provider: request building (headers, schema, image encoding) and response parsing, with recorded fixtures. No real keys in tests;
  - JSON validation and the one-retry path;
  - usage/cost accounting and same-day dedupe;
  - the Keychain key store;
  - the recipe page fetcher (allow-list, redirects, size limits) and metadata extraction;
  - Open Food Facts parsing;
  - food DB search.
- **UI tests:**
  - onboarding;
  - Quick add;
  - photo-log happy path with a stubbed provider;
  - the "no key" screen.
- **Build verification:** CI compiles, tests and produces both unsigned IPAs.
- **Conventions:**
  - SwiftLint (non-blocking in CI);
  - no force-unwraps in production code;
  - no logging of keys, photos or user text.
- Keep `CLAUDE.md` updated with build commands, conventions and architecture decisions.
- Keep `/docs/decisions.md` (short ADRs).

---

## 11. Phases (stop and report after each)

| Phase | Scope |
|---|---|
| **0 — Plan** ✅ | Architecture, design system, ADRs, sideloading findings. |
| **1 — Skeleton** ✅ | Monorepo, XcodeGen (lite/full), LakhasKit, CI with unsigned IPAs, capability probe. *(Backend skeleton now frozen.)* |
| **2 — Security foundation** ✅ *(mostly superseded)* | Kept: Keychain store, data protection, store resolver. Removed by Phase 4: device tokens, HMAC signing, API client, pinning (see ADR-020). |
| **3 — Onboarding + NutritionMath + Today** ✅ | Local data, custom tab bar, Quick add. |
| **4 — BYOK foundation** | Remove token/server code from the app; `AIProvider` abstraction with Anthropic, OpenAI, Gemini, OpenRouter; Settings → AI (provider, model list/custom ID, Keychain key, Test connection, recommended defaults); "no key" screen; local usage + cost tracking with an optional daily limit; freeze `/backend` and its CI. |
| **5 — Photo & text analysis** | Bundled food DB (USDA subset + Arabic dishes), prompts in the app, photo pipeline (downscale/EXIF strip), review screen, correction, leftovers, plate-builder search. |
| **6 — Barcode** | Open Food Facts lookup, local product library, label-photo extraction for missing products. |
| **7 — Recipes** | On-device link import (safe fetcher), screenshot import, share extension hand-off, My Recipes hub. |
| **8 — Explore** | Bundled dishes, filters, favorites, log from Explore. |
| **9 — Workouts** | Bundled exercise DB, program builder, logging, progress. |
| **10 — Water, weight, progress, widgets, reminders** | |
| **11 — Settings, backup export/import, delete-my-data, privacy manifest, Arabic & English copy review** | Review all copy in both languages for consistency, tone and completeness. Run the full app in each language. |
| **12 — Hardening** | Full test pass, accessibility audit, sideloading runbook, refresh/backup drill. |

**Later / optional:**
- iCloud (CloudKit) sync — needs the paid Apple Developer Program.
- Apple Health integration.
- On-device models (Apple Foundation Models) as a free, keyless option for text analysis.
- Android.

---

## 12. Things I will provide when you ask

- My own provider API key, for my phone only. Entered in the app's Settings → AI, never in code or chat.
- The GitHub repository (done).

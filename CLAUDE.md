# CLAUDE.md — Lakhas (لخّص)

Bilingual (Arabic default, RTL / English, LTR) AI calorie & macro tracker for iOS, **sideloaded for personal use**. The product brief is `PROJECT_PROMPT.md`; read it and `docs/` before changing behavior.

## Working rules
- **Commit after every finished step** and push (`origin` = github.com/KhaledZaki1919/lakhas, branch `main`). Small commits; end messages with the `Co-Authored-By: Claude …` line.
- Work in the phases in `PROJECT_PROMPT.md` §11 and stop to report at the end of each phase.
- Record decisions as short ADRs in `docs/decisions.md`. Keep this file current.
- Git identity for this repo: `Khaled <khaled96960@gmail.com>` (repo-local config).

## Repository map
| Path | What |
|---|---|
| `ios/` | XcodeGen specs, app (`Lakhas/`), extensions (`LakhasWidgets/`, `LakhasShare/`), app tests, `LakhasKit/` SPM package |
| `ios/LakhasKit` | `NutritionMath` (pure math) + `LakhasKit` (store resolver, Keychain, theme tokens, …) |
| `backend/` | Cloudflare Worker `lakhas-api` (Hono, zod), D1 migrations, prompts, seeds, vitest tests |
| `shared/` | `openapi.yaml` (API contract, source of truth), JSON schemas, signing test vectors |
| `admin/` | admin UI (Phase 2/7), served by the Worker behind Cloudflare Access |
| `docs/` | `architecture.md`, `design.md` (final design system), `decisions.md`, `sideloading.md`, `build-environment.md` |

## Environment
- Development machine is **Windows**; there is no Mac. iOS builds and tests run **only in GitHub Actions** (`.github/workflows/ios.yml`, `macos-15`).
- Node.js 24 is at `C:\Program Files\nodejs` (add it to `PATH` in Git Bash: `export PATH="/c/Program Files/nodejs:$PATH"`).
- No Python locally; Python scripts under `ios/scripts/` run on the macOS runner.

## Commands
Backend (from `backend/`):
```
npm install          # npm 11 install-script approvals live in package.json "allowScripts"
npm test             # vitest inside the Workers runtime (@cloudflare/vitest-plugin), migrations auto-applied
npm run typecheck    # tsc
npm run lint         # eslint + prettier --check   (npm run format to fix)
npm run build:dry    # wrangler deploy --dry-run
npm run cf-typegen  # regenerate worker-configuration.d.ts after editing wrangler.toml (secrets are typed in src/env.d.ts)
```
OpenAPI (from `shared/`): `npx @redocly/cli@2 lint openapi.yaml`

iOS (CI only; locally you can only edit):
```
xcodegen generate --spec project.full.yml   # app + widget + share extension (LAKHAS_EXTENSIONS)
xcodegen generate --spec project.yml        # lite: app only
swift test --package-path LakhasKit
python3 scripts/check-strings.py            # fails on missing ar/en translations or unknown keys
swiftlint lint
```
CI artifacts: `Lakhas-full` and `Lakhas-lite` unsigned IPAs on every push to `main` → install with Sideloadly (`docs/sideloading.md` §5).

## Conventions
**Swift / iOS**
- Swift 6 language mode, iOS 17+, SwiftUI, SwiftData. No third-party UI libraries.
- Never hand-edit `.pbxproj`; change `project.yml` / `project.full.yml`. Generated `Info.plist`s and the `.xcodeproj` are gitignored.
- No force unwraps or force casts (SwiftLint errors).
- **Strings:** every user-facing string comes from a String Catalog (`Localizable.xcstrings` per target, `InfoPlist.xcstrings`) with both `ar` and `en`. Keys are `area.name` (`tab.today`, `probe.title`); prefixes are listed in `ios/scripts/check-strings.py`, so add new areas there. Values that aren't UI text use `Text(verbatim:)`.
- **Layout:** leading/trailing only; test RTL and LTR.
- **Design:** use `Theme.Palette` / `Theme.Space` / `Theme.Radius` (LakhasKit) only, no literal colors or sizes. Tokens are in `docs/design.md`.
- **Sideloading constraints (ADR-014):** never hardcode the bundle ID, team prefix or App Group at runtime. Use `AppGroupResolver.resolve()`; extensions never call the network and never share the Keychain. Extension code is compiled only with `LAKHAS_EXTENSIONS`.
- **Data protection:** write files through `FileProtection.write`; secrets go only in `KeychainStore`.

**Backend**
- TypeScript strict, ESLint (`typescript-eslint` strict) + Prettier (width 100). No non-null assertions.
- Every route validates input with zod. Errors use `ApiError(code, status)` and the shared envelope (`src/lib/errors.ts`; codes mirror `ErrorCode` in `openapi.yaml`).
- Logs are structured JSON through `log()`; never log bodies, tokens or IPs in clear.
- Model names, caps and retention live in the D1 `config` table, never in code.
- AI calls use structured outputs (`client.messages.parse` + `zodOutputFormat`), not forced `tool_choice` (ADR-002).

## Key decisions (see docs/decisions.md)
ADR-002 structured outputs · ADR-004 caps in D1 · ADR-005 CA pinning · ADR-012 unsigned IPA from CI · ADR-013 device tokens + HMAC signing · ADR-014 free-team fallbacks · ADR-015 single tier · ADR-016 backup export · ADR-017 design A.

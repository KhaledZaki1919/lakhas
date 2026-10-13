# CLAUDE.md — Lakhas (لخّص)

Bilingual (Arabic default, RTL / English, LTR) AI calorie & macro tracker for iOS, **sideloaded for personal use**. **Bring Your Own Key, no server** (ADR-020): the app calls AI providers directly with the user's own key, and all data stays on the device. The product brief is `PROJECT_PROMPT.md`; read it and `docs/` before changing behavior.

## Working rules
- **Commit after every finished step** and push (`origin` = github.com/KhaledZaki1919/lakhas, branch `main`). Small commits; end messages with the `Co-Authored-By: Claude …` line.
- Work in the phases in `PROJECT_PROMPT.md` §11 and stop to report at the end of each phase.
- Record decisions as short ADRs in `docs/decisions.md`. Keep this file current.
- Git identity for this repo: `Khaled <khaled96960@gmail.com>` (repo-local config).

## Repository map
| Path | What |
|---|---|
| `ios/` | XcodeGen specs, app (`Lakhas/`), extensions (`LakhasWidgets/`, `LakhasShare/`), app + UI tests, `LakhasKit/` SPM package |
| `ios/LakhasKit` | `NutritionMath` (pure math) + `LakhasKit` (AI providers, models, store resolver, Keychain, theme tokens, …) |
| `shared/test-vectors/` | `nutrition.json` (used by the Swift tests) and its generator |
| `backend/`, `admin/`, `shared/frozen/` | **FROZEN** (ADR-020): former server, kept for reference only. Don't build on it |
| `docs/` | `architecture.md`, `design.md` (final design system), `decisions.md`, `sideloading.md`, `build-environment.md`; `archive/` for retired runbooks |

## Environment
- Development machine is **Windows**; there is no Mac. iOS builds and tests run **only in GitHub Actions** (`.github/workflows/ios.yml`, `macos-15`).
- Node.js 24 is at `C:\Program Files\nodejs` (in Git Bash: `export PATH="/c/Program Files/nodejs:$PATH"`). Use it for small scripts (no Python locally).
- GitHub CLI is at `C:\Program Files\GitHub CLI\gh.exe`. It uses the Git Credential Manager login through `GH_TOKEN` (set per command from `git credential fill`; never print or store it).

## Commands
iOS (CI only; locally you can only edit):
```
xcodegen generate --spec project.full.yml   # app + widget + share extension (LAKHAS_EXTENSIONS)
xcodegen generate --spec project.yml        # lite: app only
swift test --package-path LakhasKit
python3 scripts/check-strings.py            # fails on missing ar/en translations or unknown keys
swiftlint lint
```
**CI** (`ios.yml`), in order:
1. a compile-only job (full `xcodebuild.log` artifact);
2. tests;
3. `Lakhas-full` / `Lakhas-lite` unsigned IPAs.

SwiftLint is a separate, non-blocking job.

**After each push:**
1. Run `gh run watch <id> --exit-status` in the **foreground** (never a background watcher: low-memory PC).
2. On failure, read `gh run view <id> --log-failed`, fix **all** errors in one commit, push, and watch again until green.

## Conventions
**Swift / iOS**
- Swift 5 language mode (minimal concurrency checking, ADR-019), iOS 17+, SwiftUI, SwiftData. No third-party UI libraries or AI SDKs.
- Never hand-edit `.pbxproj`; change `project.yml` / `project.full.yml`. Generated `Info.plist`s and the `.xcodeproj` are gitignored.
- No force unwraps or force casts.
- **No duplicate file names** within a Swift module (SwiftPM fails with "multiple producers").
- **Strings:** every user-facing string comes from a String Catalog (`Localizable.xcstrings` per target, `InfoPlist.xcstrings`) with both `ar` and `en`. Keys are `area.name` (`tab.today`, `ai.key.title`); prefixes are listed in `ios/scripts/check-strings.py`, so add new areas there. Values that aren't UI text use `Text(verbatim:)`.
- **Accessibility identifiers** (for UI tests) start with `ax.` (`ax.onboarding.next`), so they never look like localization keys.
- **Layout:** leading/trailing only; test RTL and LTR.
- **Design:** use `Theme.Palette` / `Theme.Space` / `Theme.Radius` (LakhasKit) only, no literal colors or sizes. Tokens are in `docs/design.md`.
- **Sideloading constraints (ADR-014):** never hardcode the bundle ID, team prefix or App Group at runtime. Use `AppGroupResolver.resolve()`; extensions never call the network and never share the Keychain. Extension code is compiled only with `LAKHAS_EXTENSIONS`.
- **Data on the device only:** write files through `FileProtection.write`, which applies protection and excludes the file from backups. Secrets go only in the Keychain.
- **AI (ADR-020):**
  - Every AI call goes through `StructuredAI` (schema → provider → `Codable` + `validate()` → one retry) and records a `UsageRecord`.
  - API keys live only in `AIKeyStore`. Never log keys, photos or user text.
  - With no key, AI entry points show `NoKeyView`. Never fall back to anything else.
  - SwiftData to-many relationships are unordered, so give child rows an explicit `sortIndex`.

## Key decisions (see docs/decisions.md)
ADR-012 unsigned IPA from CI · ADR-014 free-team fallbacks · ADR-016 backup export · ADR-017 design A · ADR-019 Swift 5 mode + compile-first CI · ADR-020 Bring Your Own Key, no server, device-only data.

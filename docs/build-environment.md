# Build environment

Status: **Accepted (ADR-012)** · 2026-10-11

Development happens on **Windows 11**. iOS builds run on **GitHub Actions macOS runners**. The app is installed with **Sideloadly** using a free Apple ID (see [`sideloading.md`](sideloading.md)). A Mac is optional, later, only for faster UI iteration.

## What runs where

| Step | Where |
|---|---|
| Backend: Worker, D1/R2/KV, tests, `wrangler deploy --dry-run` | Windows (Node.js LTS) + `backend.yml` on Ubuntu runners |
| OpenAPI, prompts, seeds, admin UI, docs | Windows |
| Swift / SwiftUI code, `project.yml` | written on Windows |
| `xcodegen`, `xcodebuild`, Simulator unit tests, SwiftLint | `ios.yml` on macOS runners |
| Unsigned IPA (full + lite) | `ios.yml` → workflow artifacts |
| Install, 7-day refresh | Sideloadly on Windows + iPhone |
| App Group / widget / camera / barcode checks | the iPhone (capability probe, `sideloading.md` §4) |

## CI workflows

**`.github/workflows/ios.yml`** runs on push to `main`, on PRs, and manually. It has two jobs:
- **`test`:**
  1. `brew install xcodegen swiftlint`
  2. `xcodegen generate`
  3. SwiftLint
  4. `swift test` for the `LakhasKit` package (NutritionMath and kit tests)
  5. `xcodebuild test` on an iPhone simulator
  6. the String Catalog completeness check
- **`ipa`** (needs `test`) runs a matrix over `full` and `lite`:
  1. `xcodegen` with `LAKHAS_EXTENSIONS=1|0`
  2. `xcodebuild build -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO`
  3. `scripts/build-ipa.sh`: ad-hoc signs the extensions, then the app, with their entitlements (`codesign --force --sign -`), and zips `Payload/Lakhas.app`
  4. uploads `Lakhas-full.ipa` / `Lakhas-lite.ipa` as artifacts (kept 30 days)

**`.github/workflows/backend.yml`** runs on changes under `backend/` or `shared/`:
1. `npm ci`
2. lint
3. typecheck
4. `npm test`
5. `wrangler deploy --dry-run`

Deploying to Cloudflare is a separate manual workflow, added once the account exists.

**Cost:** GitHub bills macOS runner minutes for private repos at a 10× multiplier against the free allowance. A full iOS run is roughly 10–20 minutes. To save minutes, `ipa` runs only on `main`, not on PRs.

## Local setup (Windows)

1. Node.js LTS: `winget install OpenJS.NodeJS.LTS`, then reopen the terminal.
2. `cd backend && npm install && npm test`
3. Optional: the GitHub CLI (`winget install GitHub.cli`) to watch CI runs and download artifacts from the terminal.

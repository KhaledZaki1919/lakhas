# Build environment: Windows + macOS

Status: **Proposal for approval** · 2026-10-11

Primary workstation: **Windows 11**. iOS tooling is macOS-only, so this splits the work by what each machine can do.

## 1. What runs where

| Step | Windows | macOS needed | Physical iPhone needed |
|---|---|---|---|
| Backend (Worker, D1/R2/KV, tests, `wrangler deploy --dry-run`) | ✅ (install Node.js LTS) | — | — |
| `/shared/openapi.yaml`, prompts, seeds, admin UI, docs | ✅ | — | — |
| Writing Swift / SwiftUI code and `project.yml` | ✅ (editing only) | — | — |
| `NutritionMath` unit tests (pure Swift + Foundation) | ✅ with the Swift toolchain for Windows (optional) | or ✅ | — |
| String Catalog completeness check (JSON script) | ✅ | — | — |
| `xcodegen generate` | ❌ | ✅ (useless without Xcode anyway) | — |
| `xcodebuild` build / unit tests / UI tests, Simulator | ❌ | ✅ | — |
| SwiftUI previews, layout checks in RTL/LTR, widget gallery | ❌ | ✅ | — |
| SwiftLint | ⚠ possible, but awkward | ✅ | — |
| Code signing, provisioning profiles, entitlements | ❌ | ✅ (or CI with an App Store Connect API key) | — |
| Archive + upload to TestFlight | ❌ | ✅ (or CI) | — |
| **App Attest** (simulator unsupported) | — | — | ✅ |
| Camera, **VisionKit barcode scanner** | — | — | ✅ |
| APNs end-to-end, StoreKit sandbox purchases, Data Protection behavior when locked | — | Simulator partially | ✅ (TestFlight is fine) |

**Apple web portals work from Windows.** That covers registering the 3 bundle IDs and their capabilities (App Groups, App Attest, Push), creating the App Group, the App Store Connect app record, StoreKit products, the API key, and TestFlight testers.

## 2. Options

| | A. GitHub Actions macOS + TestFlight | B. A Mac (e.g. Mac mini, Apple silicon) | C. Cloud Mac (rented) |
|---|---|---|---|
| Upfront cost | none | hardware purchase | monthly rent |
| Running cost | macOS minutes on private repos count at **10×** against the free allowance, then billed per minute (check current GitHub pricing) | none | monthly |
| Feedback loop | push → about 10–20 min per build/test run; no interactive simulator | seconds; Claude Code can run on the Mac and drive `xcodebuild` + Simulator directly | seconds, but over remote desktop |
| Good for | CI, release builds, TestFlight uploads | day-to-day UI work (Phases 3–11), RTL/LTR visual checks | the same as B, without buying hardware |

## 3. Recommendation: A now, add B (or C) before Phase 3

**Phases 1–2 (skeleton, security):** these are mostly backend and plumbing. **GitHub Actions** is enough:
- **`ios-ci.yml`** (each push/PR): install XcodeGen → `xcodegen generate` → SwiftLint → `xcodebuild build-for-testing` / `test-without-building` on an iPhone simulator for the app, widget and LakhasKit tests → upload `.xcresult` as an artifact.
- **`ios-release.yml`** (manual or tag): archive → export → upload to **TestFlight**.
  - **Signing:** Xcode cloud-managed signing via `xcodebuild -allowProvisioningUpdates -authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`. The App Store Connect API key (.p8, Key ID, Issuer ID) lives in GitHub secrets. No certificates on disk, no fastlane.
  - **Build number:** taken from the run number.
- **`backend-ci.yml`** (Ubuntu, cheap): lint, `npm test`, `wrangler deploy --dry-run`.
- **App Attest, camera and barcode** get verified on your iPhone through TestFlight builds. TestFlight uses App Attest's *production* environment, so the server has to accept both environments with separate key records.

**From Phase 3 (UI-heavy):** a 15-minute CI loop per visual tweak, without seeing the screen, will slow every screen down and make RTL/LTR review hard. I recommend a Mac (or a cloud Mac) by then. CI stays as the gate and the release path either way.

## 4. What I need from you for option A
1. A **private GitHub repo** (name? e.g. `lakhas`), with me allowed to push.
2. **Apple Developer Team ID**.
3. An **App Store Connect API key** with the Admin role (needed for cloud-managed signing), added as repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64). Add these through GitHub's UI; never paste them into chat.
4. The bundle IDs and App Group registered in the developer portal (I can give you a step-by-step checklist).
5. On this PC: install **Node.js LTS** (`winget install OpenJS.NodeJS.LTS`) for backend work. Optionally install the Swift toolchain for Windows to run `NutritionMath` tests locally.

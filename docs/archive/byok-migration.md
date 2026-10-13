# BYOK migration — what changes (ADR-020)

Status: **proposed, awaiting approval.** Nothing below has been deleted yet.

## Deleted from the iOS app (Phase 4)

| Path | What it is |
|---|---|
| `ios/Lakhas/Features/Token/TokenEntryView.swift` | Device-token screen + QR scanner |
| `ios/Lakhas/App/AppModel.swift` | Token/session phases. Replaced by an `AISettings` model (provider, model, key status) |
| `ios/LakhasKit/Sources/LakhasKit/Security/DeviceToken.swift` | Token parsing + `TokenStore` (the generic `KeychainStore` stays) |
| `ios/LakhasKit/Sources/LakhasKit/Security/RequestSigner.swift` | HMAC request signing |
| `ios/LakhasKit/Sources/LakhasKit/API/APIClient.swift`, `API/APIModels.swift` | Client for our server |
| `ios/LakhasKit/Sources/LakhasKit/Security/CertificatePinning.swift` | SPKI pinning (if open question 1 is approved) |
| `ios/LakhasKit/Tests/LakhasKitTests/SigningTests.swift`, `APIClientTests.swift`, `CertificatePinningTests.swift`, `Fixtures/*.der` | Tests for the above |
| `ios/LakhasTests/PinningLiveTests.swift` | Live pinning test |
| `project.yml` keys `LakhasAPIBaseURL`, `LakhasPinnedSPKI`, `LAKHAS_API_BASE_URL` | Server URL and pins |
| Strings `token.*`, `probe.server*`, `probe.token*`, `log.comingPhase*` | Token screen and server rows in the probe |
| Probe "Server & token" section | Replaced by an "AI provider" status row |

## Frozen (kept in the repo, not built, not deployed)

| Path | Change |
|---|---|
| `backend/` | Add `FROZEN.md`. No code changes. |
| `admin/` | Add a note to `README.md`. |
| `shared/openapi.yaml`, `shared/test-vectors/signing.json`, `generate.mjs` | Move under `shared/frozen/`. |
| `.github/workflows/backend.yml` | Manual trigger only (`workflow_dispatch`), so pushes don't run it. |
| `docs/runbooks/deploy.md`, `docs/runbooks/pinning.md` | Move to `docs/archive/`. |

`shared/test-vectors/nutrition.json` and its generator **stay active**; the Swift NutritionMath tests use them.

## Docs updated

- `PROJECT_PROMPT.md` — revision 3 (done, pending approval)
- `docs/decisions.md` — ADR-020 (proposed). After approval: mark ADR-003/004/007/008/013/015 superseded, and annotate ADR-002/005/009/018.
- `docs/architecture.md` — rewrite: no server; provider layer, bundled data, usage tracking.
- `docs/sideloading.md`, `docs/build-environment.md`, `CLAUDE.md` — remove backend/token instructions.

## Kept as is

- Onboarding, NutritionMath, Today, tab bar, Quick add, SwiftData models, store resolver, data protection, `KeychainStore`, capability probe, CI, design system.

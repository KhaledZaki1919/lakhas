# Sideloading with a free Apple ID (Sideloadly)

Status: research findings + design, 2026-10-11. **Items marked "verify on device" will be confirmed with the Phase 1 capability probe.**

## 1. Limits of a free Apple ID (personal team)

| Limit | Effect on Lakhas |
|---|---|
| Signed apps **expire after 7 days** | Refresh weekly with Sideloadly (it can auto-refresh over USB/Wi-Fi while the PC is running). Data survives a refresh when the bundle ID and Apple ID stay the same. |
| **About 3 sideloaded apps** per device at a time | Lakhas uses 1 of them. Sources disagree on whether extensions count toward this; verify on device. |
| **10 App IDs**, each valid for about a week | The app + widget + share extension = **3 App IDs** per install. Re-installing the same bundle IDs inside the window reuses them. The lite variant uses 1. |
| No push, iCloud, App Attest, Sign in with Apple, In-App Purchase, Associated Domains | Not needed: there is no server, and data stays on the device (ADR-020). |
| Entitlements are re-issued by the signer | App Group IDs may be **rewritten** (e.g. with the team ID added). See §2. |

## 2. Capability by capability

| Capability | Works with a free team via Sideloadly? | Our design |
|---|---|---|
| **App Groups** (shared container for widgets) | **Uncertain — verify on device.** Third-party signers (AltStore, SideStore, xtool) can register one app group on free teams, but they **rewrite the group ID**. Apps that hardcode the ID then lose widget data sharing. There are reports of widgets that can't read the group after sideloading. I found nothing documenting Sideloadly's exact behavior. | Resolve the group ID **at runtime** from `embedded.mobileprovision` and fall back to the app container (ADR-014). The CI ad-hoc signature embeds our requested entitlements, so the signer can see that we want a group. |
| **Widget extension** | Installs as an extra App ID. Rendering works; **data** depends on App Groups. | Behind `LAKHAS_EXTENSIONS`. Without a shared container, widgets show "Open لخّص to set up widgets". |
| **Share extension** | Installs as an extra App ID. iOS gives share extensions no supported way to open their host app, so the hand-off needs a shared container. | Behind the same flag. With an App Group, it drops the link or image into a pending-imports folder, and the app picks it up on next launch. It always copies the link to the clipboard too, with a marker type, because free Apple IDs usually have no App Group. When the app opens, it offers "Import a recipe?" (ADR-025). Images get re-picked from Photos in the app. |
| **Keychain** (own app) | Works: every signed app has its default access group (`<team prefix>.<bundle id>`). | Store the token with no explicit access group. |
| **Keychain sharing** (app ↔ extensions) | Group names carry the team prefix, which changes with the signer; unreliable. | **Not used.** Extensions never touch the token. |
| **Data Protection** | Per-file protection classes work without any entitlement. | Set `.completeUntilFirstUserAuthentication` on the store and image files. |
| **Local notifications** | Work (no entitlement). | Reminders stay local. |
| **Camera, Photos, VisionKit barcode scanner** | Work (privacy usage strings only). | No change. |
| **Background App Refresh** | Works. | Not required. |

### First device test (2026-10-12, Lakhas-full, Sideloadly, free Apple ID)
- **Worked:** installs and launches; Keychain works.
- **Probe report:** "No signing profile", no App Group in use, storage not shared.
- **Probe fix:** the probe now separates *missing* from *unreadable*, and decodes the profile's CMS envelope properly (some signers chunk the plist, which defeats a text search). It also reads the team prefix from the Keychain and lists the entitlements the profile grants.
- **Likely outcome:** Sideloadly lists custom entitlements as a paid-program feature ([changelog](https://sideloadly.io/changelog.html)), so on a free Apple ID it most likely **drops the App Group**. Lakhas then runs in the "no usable group" row below: everything works except live widget data and the share extension's queue (it falls back to copying the link). To be confirmed by the next probe report.

## 3. Fallback matrix

| Scenario | Widgets | Share extension | Everything else |
|---|---|---|---|
| Full IPA, App Group resolved | ✅ live data | ✅ | ✅ |
| Full IPA, no usable group | Placeholder ("open the app") | Link copied → paste in app; images: re-pick in app | ✅ |
| Full IPA rejected or App ID limit hit | — | — | Install **lite** IPA |
| Lite IPA | — | In-app paste + PhotosPicker | ✅ |

Settings → **Sideloading status** shows: build variant, resolved App Group (or "none"), whether the store is shared, whether the widget has checked in, the bundle ID, and the token status.

## 4. Capability probe (Phase 1)

A debug-visible screen and a tiny probe widget that:
1. print the bundle ID, the team prefix from `embedded.mobileprovision`, and the App Group IDs in the profile;
2. try to open the App Group container and write/read a heartbeat file;
3. let the widget read that heartbeat and write its own back, so the app can show "widget can see app data: yes/no";
4. write/read/delete a Keychain test item.

**Your test after Phase 1:** install `Lakhas-full.ipa` with Sideloadly, add the probe widget, open the probe screen, and send me a screenshot. That decides whether widgets get live data in Phase 9.

## 5. Install & refresh runbook (short version)

1. GitHub → Actions → latest `main` run → download `Lakhas-full` (or `Lakhas-lite`) → unzip to get the `.ipa`.
2. Sideloadly → plug in the iPhone → drag in the IPA → enter your Apple ID → Start. **Keep the same bundle ID every time** (don't enable "change bundle ID"), or the app gets a fresh, empty container.
3. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID. On iOS 16+ also turn on Settings → Privacy & Security → **Developer Mode** (one-time).
4. Every 7 days: refresh in Sideloadly (or enable its auto-refresh). Updating to a newer IPA the same way keeps your data.
5. Before risky changes (new Apple ID, new phone): Settings → Backup → Export.

## Sources
- [Apple — Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
- [AltStore FAQ — App IDs](https://faq.altstore.io/altstore-world/app-ids)
- [xtool PR #284 — one app group on free teams](https://github.com/xtool-org/xtool/pull/284)
- [SideStore issue #1437 — App Groups for extensions/widgets](https://github.com/SideStore/SideStore/issues/1437)
- [beancount-ledger-web PR #386 — widget sharing after re-signing](https://github.com/qiaoborui/beancount-ledger-web/pull/386)
- [Corellium — Sideloadly](https://support.corellium.com/features/apps/sideloadly)
- [Sideloadly](https://sideloadly.io/index.html)

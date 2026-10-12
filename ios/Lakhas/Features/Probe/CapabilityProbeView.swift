import LakhasKit
import SwiftUI
#if LAKHAS_EXTENSIONS
import WidgetKit
#endif

/// Shows what actually works on this sideloaded install (docs/sideloading.md §4):
/// the signer's profile and App Group, whether the widget shares our container, and the Keychain.
struct CapabilityProbeView: View {
    @Environment(AppModel.self) private var model
    @State private var report = ProbeReport.collect()
    @State private var keychainOK: Bool?

    var body: some View {
        List {
            Section("probe.section.server") {
                LabeledContent("probe.server", value: model.configuration?.baseURL.host
                    .flatMap { model.isServerConfigured ? $0 : nil } ?? String(localized: "probe.server.notConfigured"))
                LabeledContent("probe.token", value: model.token.map { "\($0.tokenId.prefix(4))…" }
                    ?? String(localized: "probe.none"))
                if model.token != nil {
                    Button("probe.token.replace", role: .destructive) { model.forgetToken() }
                } else {
                    Button("probe.token.enter") { model.forgetToken() }
                }
            }
            Section("probe.section.build") {
                LabeledContent("probe.variant", value: report.variant)
                LabeledContent("probe.bundleID", value: report.bundleID)
                LabeledContent("probe.team", value: report.team)
                LabeledContent("probe.profileFile", value: report.profileFile)
                LabeledContent("probe.profileGroups", value: report.profileGroups)
                LabeledContent("probe.entitlements", value: report.entitlements)
            }
            Section("probe.section.storage") {
                LabeledContent("probe.resolvedGroup", value: report.resolvedGroup)
                LabeledContent("probe.storeShared", value: report.storeShared)
                LabeledContent("probe.widgetSeen", value: report.widgetSeen)
            }
            Section("probe.section.keychain") {
                Button("probe.keychain.run") {
                    keychainOK = (try? KeychainStore(service: ProbeReport.keychainService).selfTest().get()) != nil
                }
                if let keychainOK {
                    LabeledContent("probe.keychain.result", value: ProbeReport.yesNo(keychainOK))
                }
            }
            Section {
                Button("probe.refresh", action: refresh)
                ShareLink(item: report.text) {
                    Label("probe.share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("probe.title")
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let location = AppGroupResolver.resolve()
        try? HeartbeatStore(location: location).write(Heartbeat(
            role: .app,
            date: .now,
            bundleID: Bundle.main.bundleIdentifier ?? "",
            appGroupID: location.appGroupID
        ))
        #if LAKHAS_EXTENSIONS
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        report = ProbeReport.collect()
    }
}

struct ProbeReport {
    static let keychainService = "lakhas.probe"

    let variant: String
    let bundleID: String
    let team: String
    let profileFile: String
    let profileGroups: String
    let entitlements: String
    let resolvedGroup: String
    let storeShared: String
    let widgetSeen: String

    static func collect(bundle: Bundle = .main) -> ProbeReport {
        let none = String(localized: "probe.none")
        let status = ProvisioningProfile.inspect(bundle: bundle)
        let profile = status.profile
        let location = AppGroupResolver.resolve(bundle: bundle)
        let widgetDate = HeartbeatStore(location: location).read(.widget)?.date

        #if LAKHAS_EXTENSIONS
        let variant = String(localized: "probe.variant.full")
        #else
        let variant = String(localized: "probe.variant.lite")
        #endif

        return ProbeReport(
            variant: variant,
            bundleID: bundle.bundleIdentifier ?? none,
            team: profile?.teamIdentifiers.first ?? keychainTeam() ?? none,
            profileFile: describe(status),
            profileGroups: profile.map { $0.appGroups.isEmpty ? none : $0.appGroups.joined(separator: ", ") }
                ?? String(localized: "probe.noProfile"),
            entitlements: profile.map { $0.entitlementKeys.isEmpty ? none : $0.entitlementKeys.joined(separator: ", ") }
                ?? none,
            resolvedGroup: location.appGroupID ?? none,
            storeShared: yesNo(location.isShared),
            widgetSeen: widgetDate.map { $0.formatted(date: .abbreviated, time: .shortened) }
                ?? String(localized: "probe.widget.never")
        )
    }

    static func yesNo(_ value: Bool) -> String {
        value ? String(localized: "common.yes") : String(localized: "common.no")
    }

    private static func describe(_ status: ProvisioningProfile.Status) -> String {
        switch status {
        case .missing:
            return String(localized: "probe.profile.missing")
        case .unreadable(let byteCount):
            return "\(String(localized: "probe.profile.unreadable")) (\(byteCount) B)"
        case .parsed(let profile):
            return [String(localized: "probe.profile.parsed"), profile.name]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    /// Team prefix of our default Keychain access group; works without a readable profile.
    private static func keychainTeam() -> String? {
        guard let group = KeychainStore(service: keychainService).defaultAccessGroup(),
              let prefix = group.split(separator: ".").first else { return nil }
        return "\(prefix) (\(String(localized: "probe.team.fromKeychain")))"
    }

    /// Plain-text report for the share sheet (to send back during the sideloading test).
    var text: String {
        [
            "\(String(localized: "probe.variant")): \(variant)",
            "\(String(localized: "probe.bundleID")): \(bundleID)",
            "\(String(localized: "probe.team")): \(team)",
            "\(String(localized: "probe.profileFile")): \(profileFile)",
            "\(String(localized: "probe.profileGroups")): \(profileGroups)",
            "\(String(localized: "probe.entitlements")): \(entitlements)",
            "\(String(localized: "probe.resolvedGroup")): \(resolvedGroup)",
            "\(String(localized: "probe.storeShared")): \(storeShared)",
            "\(String(localized: "probe.widgetSeen")): \(widgetSeen)",
        ].joined(separator: "\n")
    }
}

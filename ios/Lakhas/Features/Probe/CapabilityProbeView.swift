import LakhasKit
import SwiftUI
#if LAKHAS_EXTENSIONS
import WidgetKit
#endif

/// Shows what actually works on this sideloaded install (docs/sideloading.md §4):
/// the signer's App Group, whether the widget shares our container, and the Keychain.
struct CapabilityProbeView: View {
    @State private var report = ProbeReport.collect()
    @State private var keychainOK: Bool?

    var body: some View {
        List {
            Section("probe.section.build") {
                LabeledContent("probe.variant", value: report.variant)
                LabeledContent("probe.bundleID", value: report.bundleID)
                LabeledContent("probe.team", value: report.team)
                LabeledContent("probe.profileGroups", value: report.profileGroups)
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
    let profileGroups: String
    let resolvedGroup: String
    let storeShared: String
    let widgetSeen: String

    static func collect(bundle: Bundle = .main) -> ProbeReport {
        let none = String(localized: "probe.none")
        let profile = ProvisioningProfile.load(from: bundle)
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
            team: profile?.teamIdentifiers.first ?? none,
            profileGroups: profile.map { $0.appGroups.isEmpty ? none : $0.appGroups.joined(separator: ", ") }
                ?? String(localized: "probe.noProfile"),
            resolvedGroup: location.appGroupID ?? none,
            storeShared: yesNo(location.isShared),
            widgetSeen: widgetDate.map { $0.formatted(date: .abbreviated, time: .shortened) }
                ?? String(localized: "probe.widget.never")
        )
    }

    static func yesNo(_ value: Bool) -> String {
        value ? String(localized: "common.yes") : String(localized: "common.no")
    }

    /// Plain-text report for the share sheet (to send back during the sideloading test).
    var text: String {
        [
            "\(String(localized: "probe.variant")): \(variant)",
            "\(String(localized: "probe.bundleID")): \(bundleID)",
            "\(String(localized: "probe.team")): \(team)",
            "\(String(localized: "probe.profileGroups")): \(profileGroups)",
            "\(String(localized: "probe.resolvedGroup")): \(resolvedGroup)",
            "\(String(localized: "probe.storeShared")): \(storeShared)",
            "\(String(localized: "probe.widgetSeen")): \(widgetSeen)",
        ].joined(separator: "\n")
    }
}

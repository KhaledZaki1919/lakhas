import Foundation

/// The parts of `embedded.mobileprovision` the app needs at runtime.
///
/// Sideloading tools re-sign the app and may rewrite the App Group identifiers (ADR-014),
/// so the profile embedded at install time is the source of truth, not the compiled value.
public struct ProvisioningProfile: Sendable, Equatable {
    public let name: String?
    public let teamIdentifiers: [String]
    public let appGroups: [String]
    public let applicationIdentifier: String?
    public let expirationDate: Date?

    /// Loads the profile embedded in `bundle` (the `.app` or `.appex`). Returns nil in the
    /// Simulator and in unsigned builds, which carry no profile.
    public static func load(from bundle: Bundle = .main) -> ProvisioningProfile? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    /// The file is a CMS envelope around an XML plist; the plist is extracted by its markers
    /// instead of verifying the signature (we only read, never trust it for security).
    public static func parse(_ data: Data) -> ProvisioningProfile? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
            as? [String: Any] else { return nil }

        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return ProvisioningProfile(
            name: plist["Name"] as? String,
            teamIdentifiers: plist["TeamIdentifier"] as? [String] ?? [],
            appGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            applicationIdentifier: entitlements["application-identifier"] as? String,
            expirationDate: plist["ExpirationDate"] as? Date
        )
    }
}

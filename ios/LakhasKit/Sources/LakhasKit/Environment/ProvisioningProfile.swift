import Foundation

/// The parts of `embedded.mobileprovision` the app needs at runtime.
///
/// Sideloading tools re-sign the app and may rewrite or drop the App Group identifiers
/// (ADR-014), so the profile embedded at install time is the source of truth, not the
/// compiled value.
public struct ProvisioningProfile: Sendable, Equatable {
    public let name: String?
    public let teamIdentifiers: [String]
    public let appGroups: [String]
    public let applicationIdentifier: String?
    public let expirationDate: Date?
    /// All entitlement keys granted by the profile (for the capability probe).
    public let entitlementKeys: [String]

    /// What was found in the bundle; distinguishes "no file" from "file we couldn't read".
    public enum Status: Sendable, Equatable {
        case missing
        case unreadable(byteCount: Int)
        case parsed(ProvisioningProfile)

        public var profile: ProvisioningProfile? {
            if case .parsed(let profile) = self { return profile }
            return nil
        }
    }

    public static func inspect(bundle: Bundle = .main) -> Status {
        let url = bundle.bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url) else { return .missing }
        guard let profile = parse(data) else { return .unreadable(byteCount: data.count) }
        return .parsed(profile)
    }

    /// Loads the profile embedded in `bundle` (the `.app` or `.appex`). Returns nil in the
    /// Simulator and in unsigned builds, which carry no profile.
    public static func load(from bundle: Bundle = .main) -> ProvisioningProfile? {
        inspect(bundle: bundle).profile
    }

    /// Decodes the CMS envelope properly first; falls back to locating the XML plist by its
    /// markers. We only read the profile and never trust it for security decisions.
    public static func parse(_ data: Data) -> ProvisioningProfile? {
        if let payload = CMSContent.extract(data), let profile = profile(fromPlist: payload) {
            return profile
        }
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        return profile(fromPlist: data.subdata(in: start.lowerBound..<end.upperBound))
    }

    private static func profile(fromPlist data: Data) -> ProvisioningProfile? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any] else { return nil }

        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return ProvisioningProfile(
            name: plist["Name"] as? String,
            teamIdentifiers: plist["TeamIdentifier"] as? [String] ?? [],
            appGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            applicationIdentifier: entitlements["application-identifier"] as? String,
            expirationDate: plist["ExpirationDate"] as? Date,
            entitlementKeys: entitlements.keys.sorted()
        )
    }
}

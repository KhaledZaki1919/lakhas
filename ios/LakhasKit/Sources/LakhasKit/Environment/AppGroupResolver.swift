import Foundation

/// Where the app, widgets and share extension keep their files.
public struct StoreLocation: Sendable, Equatable {
    public let directory: URL
    /// The App Group in use, or nil when falling back to the app's own container.
    public let appGroupID: String?

    public var isShared: Bool { appGroupID != nil }
}

/// Resolves the shared container at runtime (ADR-014):
/// 1. App Groups listed in the embedded provisioning profile (as rewritten by the signer),
/// 2. the compiled default from Info.plist (`LakhasAppGroup`),
/// 3. the target's own Application Support directory.
public enum AppGroupResolver {
    public static let infoPlistKey = "LakhasAppGroup"

    public static func resolve(bundle: Bundle = .main) -> StoreLocation {
        let profileGroups = ProvisioningProfile.load(from: bundle)?.appGroups ?? []
        let compiled = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String
        return resolve(
            candidates: candidateIDs(profileGroups: profileGroups, compiled: compiled),
            containerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) },
            fallback: defaultFallbackDirectory()
        )
    }

    static func candidateIDs(profileGroups: [String], compiled: String?) -> [String] {
        var seen = Set<String>()
        return (profileGroups + [compiled].compactMap { $0 }).filter { seen.insert($0).inserted }
    }

    static func resolve(candidates: [String], containerURL: (String) -> URL?, fallback: URL) -> StoreLocation {
        for id in candidates {
            if let url = containerURL(id), isWritable(url) {
                return StoreLocation(directory: url, appGroupID: id)
            }
        }
        return StoreLocation(directory: fallback, appGroupID: nil)
    }

    /// `containerURL` can return a path even when the entitlement is missing, so write to it.
    static func isWritable(_ directory: URL) -> Bool {
        let probe = directory.appendingPathComponent(".lakhas-write-probe")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    static func defaultFallbackDirectory() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Lakhas", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

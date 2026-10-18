import Foundation

/// Links handed from the share extension to the app through the shared container
/// (docs/sideloading.md §2). The app offers each queued link when it opens (`ImportOffer`).
public struct PendingImport: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let url: URL
    public let createdAt: Date
}

public struct PendingImportQueue: Sendable {
    /// Pasteboard type the share extension adds next to the copied link, so the app can tell a
    /// shared link from any copied one without reading the clipboard.
    public static let clipboardMarkerType = "lakhas.shared-link"
    /// The copied link expires after this long.
    public static let clipboardLifetime: TimeInterval = 3600

    public let directory: URL

    public init(location: StoreLocation) {
        self.init(directory: location.directory.appendingPathComponent("PendingImports", isDirectory: true))
    }

    init(directory: URL) {
        self.directory = directory
    }

    @discardableResult
    public func enqueue(url: URL, now: Date = .now) throws -> PendingImport {
        let item = PendingImport(id: UUID(), url: url, createdAt: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try FileProtection.write(
            try encoder.encode(item),
            to: directory.appendingPathComponent("\(item.id.uuidString).json")
        )
        return item
    }

    /// Oldest first.
    public func list() -> [PendingImport] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(PendingImport.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(_ item: PendingImport) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(item.id.uuidString).json"))
    }
}

import Foundation

/// A timestamp each process writes into the store so the others can tell whether they
/// really share a container (capability probe, docs/sideloading.md §4).
public struct Heartbeat: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        case app, widget, share
    }

    public let role: Role
    public let date: Date
    public let bundleID: String
    public let appGroupID: String?

    public init(role: Role, date: Date, bundleID: String, appGroupID: String?) {
        self.role = role
        self.date = date
        self.bundleID = bundleID
        self.appGroupID = appGroupID
    }
}

public struct HeartbeatStore: Sendable {
    public let directory: URL

    public init(location: StoreLocation) {
        self.init(directory: location.directory.appendingPathComponent("Probe", isDirectory: true))
    }

    init(directory: URL) {
        self.directory = directory
    }

    public func write(_ heartbeat: Heartbeat) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try FileProtection.write(try encoder.encode(heartbeat), to: url(for: heartbeat.role))
    }

    public func read(_ role: Heartbeat.Role) -> Heartbeat? {
        guard let data = try? Data(contentsOf: url(for: role)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Heartbeat.self, from: data)
    }

    private func url(for role: Heartbeat.Role) -> URL {
        directory.appendingPathComponent("\(role.rawValue)-heartbeat.json")
    }
}

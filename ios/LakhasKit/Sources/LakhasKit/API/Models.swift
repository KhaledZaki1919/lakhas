import Foundation

/// Response shapes from shared/openapi.yaml.

public struct CapUsage: Codable, Sendable, Equatable {
    public let used: Int
    public let limit: Int

    public var remaining: Int { max(0, limit - used) }
}

public struct CapStatus: Codable, Sendable, Equatable {
    public struct Caps: Codable, Sendable, Equatable {
        public let photo: CapUsage
        public let text: CapUsage
        public let recipe: CapUsage
        public let barcode: CapUsage
        public let correct: CapUsage
    }

    public let day: String
    public let resetsAt: Date
    public let caps: Caps
    public let global: CapUsage
}

public struct DeviceInfo: Codable, Sendable, Equatable {
    public let label: String
    public let caps: CapStatus
    public let serverTime: Date
}

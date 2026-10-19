import Foundation

// Wire types of the lakhas-api Worker (backend/src/api). Field names match the server's JSON.

public struct SessionResponse: Codable, Equatable, Sendable {
    public let deviceId: String
    public let deviceSecret: String
    public let accessToken: String
    public let accessExpiresAt: Int64
    public let refreshToken: String
    public let refreshExpiresAt: Int64

    public init(deviceId: String, deviceSecret: String, accessToken: String, accessExpiresAt: Int64,
                refreshToken: String, refreshExpiresAt: Int64) {
        self.deviceId = deviceId
        self.deviceSecret = deviceSecret
        self.accessToken = accessToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshToken = refreshToken
        self.refreshExpiresAt = refreshExpiresAt
    }
}

public struct TokenResponse: Codable, Equatable, Sendable {
    public let accessToken: String
    public let accessExpiresAt: Int64
    public let refreshToken: String
    public let refreshExpiresAt: Int64
}

public struct ServerUser: Codable, Equatable, Sendable {
    public let id: String
    public let email: String
}

public struct PreloginResponse: Codable, Sendable {
    public struct KDF: Codable, Sendable {
        public let name: String
        public let iterations: Int
    }

    public let kdf: KDF
    public let salts: AccountKeys.Salts
    public let recoverySalt: String
}

struct SignupResponse: Decodable {
    let user: ServerUser
    let session: SessionResponse
}

struct LoginResponse: Decodable {
    struct Keys: Decodable {
        let envelope: AccountKeys.Envelope?
    }

    let user: ServerUser
    let session: SessionResponse
    let keys: Keys
}

struct RecoveryStartResponse: Decodable {
    let ticket: String
    let envelope: AccountKeys.Envelope?
}

struct ResetResponse: Decodable {
    let user: ServerUser
    let session: SessionResponse
}

/// What Settings → Account shows.
public struct AccountInfo: Decodable, Equatable, Sendable {
    public struct User: Decodable, Equatable, Sendable {
        public let id: String
        public let email: String
        public let createdAt: Int64
        public let shareProducts: Bool
    }

    public struct Device: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let platform: String
        public let appVersion: String?
        public let status: String
        public let createdAt: Int64
        public let lastSeenAt: Int64?
        public let current: Bool

        public var isActive: Bool { status == "active" }
    }

    public let user: User
    public let devices: [Device]
}

struct OKResponse: Decodable {
    let ok: Bool
}

struct DeviceInfo: Encodable {
    let label: String
    let platform = "ios"
    let appVersion: String?
}

/// The server's error envelope: `{ "error": { "code", "message", "retryable" } }`.
struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String?
        let retryable: Bool?
    }

    let error: Body
}

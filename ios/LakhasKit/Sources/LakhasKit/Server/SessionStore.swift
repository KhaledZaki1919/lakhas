import Foundation

/// Where account secrets live: the Keychain on the phone, memory in tests and UI tests.
public protocol SecretStore: Sendable {
    func save(_ data: Data, account: String) throws
    func read(account: String) throws -> Data?
    func delete(account: String) throws
}

extension KeychainStore: SecretStore {}

/// In-memory secrets for unit and UI tests (`-uiTesting`). Never used otherwise.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    public init() {}

    public func save(_ data: Data, account: String) throws {
        lock.withLock { items[account] = data }
    }

    public func read(account: String) throws -> Data? {
        lock.withLock { items[account] }
    }

    public func delete(account: String) throws {
        _ = lock.withLock { items.removeValue(forKey: account) }
    }
}

/// The signed-in device (ADR-027 §1). Kept in the Keychain (`AfterFirstUnlockThisDeviceOnly`,
/// this app only), never in UserDefaults and never in a backup.
public struct StoredSession: Codable, Equatable, Sendable {
    public var userId: String
    public var email: String
    public var deviceId: String
    /// 32 bytes, base64url: signs every request (LK2).
    public var deviceSecret: String
    public var accessToken: String
    /// Unix ms.
    public var accessExpiresAt: Int64
    public var refreshToken: String
    public var refreshExpiresAt: Int64

    public init(userId: String, email: String, response: SessionResponse) {
        self.userId = userId
        self.email = email
        deviceId = response.deviceId
        deviceSecret = response.deviceSecret
        accessToken = response.accessToken
        accessExpiresAt = response.accessExpiresAt
        refreshToken = response.refreshToken
        refreshExpiresAt = response.refreshExpiresAt
    }

    public mutating func apply(_ tokens: TokenResponse) {
        accessToken = tokens.accessToken
        accessExpiresAt = tokens.accessExpiresAt
        refreshToken = tokens.refreshToken
        refreshExpiresAt = tokens.refreshExpiresAt
    }

    /// True when the access token is gone or about to expire.
    public func needsRefresh(now: Date = .now) -> Bool {
        accessExpiresAt - 30_000 <= Int64(now.timeIntervalSince1970 * 1000)
    }
}

/// The session and the backup data key in one place.
public struct SessionStore: Sendable {
    public static let keychainService = "lakhas.account"
    private static let sessionAccount = "session"
    private static let dataKeyAccount = "backup-data-key"

    private let secrets: SecretStore

    public init(secrets: SecretStore = KeychainStore(service: SessionStore.keychainService,
                                                     accessibility: .afterFirstUnlockThisDeviceOnly)) {
        self.secrets = secrets
    }

    public func session() -> StoredSession? {
        guard let data = try? secrets.read(account: Self.sessionAccount) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    public func save(_ session: StoredSession) throws {
        try secrets.save(JSONEncoder().encode(session), account: Self.sessionAccount)
    }

    /// The random key that encrypts backups (Phase 10). Kept after sign in so daily backups
    /// don't ask for the password.
    public func dataKey() -> Data? {
        try? secrets.read(account: Self.dataKeyAccount)
    }

    public func saveDataKey(_ key: Data) throws {
        try secrets.save(key, account: Self.dataKeyAccount)
    }

    /// Signs this phone out locally: session and data key are erased.
    public func clear() {
        try? secrets.delete(account: Self.sessionAccount)
        try? secrets.delete(account: Self.dataKeyAccount)
    }
}

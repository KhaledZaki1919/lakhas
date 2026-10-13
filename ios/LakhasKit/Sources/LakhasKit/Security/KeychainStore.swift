import Foundation
import Security

public enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
    case unexpectedData
}

/// Generic-password items in the app's default access group only. No explicit access group
/// and no Keychain sharing: the team prefix changes with the signer (ADR-014).
/// "ThisDeviceOnly" items are never synced to iCloud Keychain or included in backups.
public struct KeychainStore: Sendable {
    public enum Accessibility: Sendable {
        /// Readable after the first unlock (background work, widgets).
        case afterFirstUnlockThisDeviceOnly
        /// Readable only while the device is unlocked (API keys, ADR-020).
        case whenUnlockedThisDeviceOnly

        var value: CFString {
            switch self {
            case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
        }
    }

    public let service: String
    public let accessibility: Accessibility

    public init(service: String, accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly) {
        self.service = service
        self.accessibility = accessibility
    }

    public func save(_ data: Data, account: String) throws {
        try delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility.value
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.unexpectedData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    /// Write, read back and delete a random value. Used by the capability probe.
    public func selfTest() -> Result<Void, KeychainError> {
        let account = "probe-\(UUID().uuidString)"
        let value = Data(UUID().uuidString.utf8)
        do {
            try save(value, account: account)
            defer { try? delete(account: account) }
            guard try read(account: account) == value else { return .failure(.unexpectedData) }
            return .success(())
        } catch let error as KeychainError {
            return .failure(error)
        } catch {
            return .failure(.unexpectedData)
        }
    }

    /// The access group iOS assigns to our items, e.g. `ABCDE12345.com.khaled.lakhas`.
    /// Its first component is the signing team's App ID prefix, which works even when the
    /// provisioning profile can't be read (capability probe).
    public func defaultAccessGroup() -> String? {
        let account = "probe-group-\(UUID().uuidString)"
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data("probe".utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemAdd(query as CFDictionary, &result)
        defer { try? delete(account: account) }
        guard status == errSecSuccess, let attributes = result as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessGroup as String] as? String
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

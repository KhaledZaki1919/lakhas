import Foundation

/// A device access token issued in the admin panel (ADR-013): `lk1_<tokenId>_<secret>`,
/// where the secret is 32 random bytes in base64url. The secret never leaves the device.
public struct DeviceToken: Sendable, Equatable {
    public let tokenId: String
    public let secret: Data

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("lk1_") else { return nil }
        let rest = trimmed.dropFirst(4)
        // The secret is base64url and may itself contain "_", so split at the first one only.
        guard let separator = rest.firstIndex(of: "_") else { return nil }
        let tokenId = String(rest[..<separator])
        let secretText = String(rest[rest.index(after: separator)...])

        guard (12...32).contains(tokenId.count),
              tokenId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              secretText.count == 43,
              let secret = Data(base64URLEncoded: secretText), secret.count == 32
        else { return nil }
        self.tokenId = tokenId
        self.secret = secret
    }

    public var text: String { "lk1_\(tokenId)_\(secret.base64URLEncodedString())" }
}

/// Keychain persistence for the device token (`AfterFirstUnlockThisDeviceOnly`).
public struct TokenStore: Sendable {
    private let keychain: KeychainStore
    private static let account = "device-token"

    public init(keychain: KeychainStore = KeychainStore(service: "lakhas.device")) {
        self.keychain = keychain
    }

    public func load() -> DeviceToken? {
        guard let data = try? keychain.read(account: Self.account),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return DeviceToken(text)
    }

    public func save(_ token: DeviceToken) throws {
        try keychain.save(Data(token.text.utf8), account: Self.account)
    }

    public func clear() {
        try? keychain.delete(account: Self.account)
    }
}

extension Data {
    init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

import CommonCrypto
import CryptoKit
import Foundation

/// The phone-side key derivation of ADR-027 §1–2. Shared vectors:
/// shared/test-vectors/account-keys.json (generated with Node's crypto).
///
///     stretched   = PBKDF2-SHA256(NFC(password), kdfSalt, iterations)      never stored, never sent
///     authKey     = HKDF(stretched, authSalt, "lakhas/auth/v1")            the only value sent
///     passwordKEK = HKDF(stretched, encSalt,  "lakhas/backup-kek/v1")      wraps the backup key
///     recoveryAuth/KEK = HKDF(code bytes, recoverySalt, "lakhas/recovery-auth|kek/v1")
public enum AccountKeys {
    public static let kdfName = "pbkdf2-sha256"
    public static let defaultIterations = 600_000
    public static let minimumPasswordLength = 10

    public struct Salts: Codable, Equatable, Sendable {
        public let kdf: String
        public let auth: String
        public let enc: String

        public init(kdf: String, auth: String, enc: String) {
            self.kdf = kdf
            self.auth = auth
            self.enc = enc
        }

        public static func random() -> Salts {
            Salts(kdf: Data.random(count: 16).base64URLEncodedString,
                  auth: Data.random(count: 16).base64URLEncodedString,
                  enc: Data.random(count: 16).base64URLEncodedString)
        }
    }

    public struct PasswordKeys: Sendable {
        /// Sent to the server (base64url, 32 bytes).
        public let authKey: Data
        /// Wraps the backup data key. Never leaves the phone.
        public let passwordKEK: Data
    }

    public struct RecoveryKeys: Sendable {
        public let recoveryAuth: Data
        public let recoveryKEK: Data
    }

    public enum KeyError: Error, Equatable {
        case badSalt, derivationFailed, badEnvelope, wrongKey
    }

    // MARK: Password

    public static func stretch(password: String, salt: Data, iterations: Int) throws -> Data {
        let passwordBytes = Data(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { out in
            passwordBytes.withUnsafeBytes { pass in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pass.baseAddress?.assumingMemoryBound(to: CChar.self), passwordBytes.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        out.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw KeyError.derivationFailed }
        return derived
    }

    /// Slow on purpose (600,000 rounds): call it off the main thread.
    public static func passwordKeys(password: String, salts: Salts, iterations: Int) throws -> PasswordKeys {
        guard let kdfSalt = Data(base64URL: salts.kdf), let authSalt = Data(base64URL: salts.auth),
              let encSalt = Data(base64URL: salts.enc) else { throw KeyError.badSalt }
        let stretched = try stretch(password: password, salt: kdfSalt, iterations: iterations)
        return PasswordKeys(authKey: hkdf(stretched, salt: authSalt, info: "lakhas/auth/v1"),
                            passwordKEK: hkdf(stretched, salt: encSalt, info: "lakhas/backup-kek/v1"))
    }

    // MARK: Recovery code

    public static func recoveryKeys(code: RecoveryCode, salt: String) throws -> RecoveryKeys {
        guard let saltBytes = Data(base64URL: salt) else { throw KeyError.badSalt }
        return RecoveryKeys(recoveryAuth: hkdf(code.bytes, salt: saltBytes, info: "lakhas/recovery-auth/v1"),
                            recoveryKEK: hkdf(code.bytes, salt: saltBytes, info: "lakhas/recovery-kek/v1"))
    }

    // MARK: Data key envelopes

    public enum EnvelopeKind: String, Sendable {
        case password, recovery
    }

    public struct Envelope: Codable, Equatable, Sendable {
        public let nonce: String
        public let wrapped: String

        public init(nonce: String, wrapped: String) {
            self.nonce = nonce
            self.wrapped = wrapped
        }
    }

    public static func newDataKey() -> Data { Data.random(count: 32) }

    public static func wrap(dataKey: Data, with kek: Data, kind: EnvelopeKind, nonce: Data = .random(count: 12)) throws -> Envelope {
        let box = try AES.GCM.seal(dataKey, using: SymmetricKey(data: kek), nonce: AES.GCM.Nonce(data: nonce),
                                   authenticating: aad(kind))
        return Envelope(nonce: nonce.base64URLEncodedString, wrapped: (box.ciphertext + box.tag).base64URLEncodedString)
    }

    public static func unwrap(_ envelope: Envelope, with kek: Data, kind: EnvelopeKind) throws -> Data {
        guard let nonce = Data(base64URL: envelope.nonce), let wrapped = Data(base64URL: envelope.wrapped),
              wrapped.count == 48 else { throw KeyError.badEnvelope }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: wrapped.prefix(32),
                                            tag: wrapped.suffix(16))
            return try AES.GCM.open(box, using: SymmetricKey(data: kek), authenticating: aad(kind))
        } catch {
            throw KeyError.wrongKey
        }
    }

    // MARK: Helpers

    static func hkdf(_ input: Data, salt: Data, info: String) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: input), salt: salt,
                                         info: Data(info.utf8), outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }

    private static func aad(_ kind: EnvelopeKind) -> Data { Data("lakhas/dek/v1/\(kind.rawValue)".utf8) }
}

/// The one-time recovery code (ADR-027 §2): 128 random bits shown as 26 base32 characters in
/// groups of four. Typing is forgiving: case, spaces and dashes don't matter, and 0/1/8 are read
/// as O/I/B (they aren't in the alphabet).
public struct RecoveryCode: Equatable, Sendable {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == 16 else { return nil }
        self.bytes = bytes
    }

    public static func generate() -> RecoveryCode {
        RecoveryCode(unchecked: .random(count: 16))
    }

    private init(unchecked bytes: Data) { self.bytes = bytes }

    /// Parses what the user typed or pasted.
    public init?(typed text: String) {
        let cleaned = text.uppercased().compactMap { character -> Character? in
            switch character {
            case "0": "O"
            case "1": "I"
            case "8": "B"
            default: Self.alphabet.contains(character) ? character : nil
            }
        }
        guard cleaned.count == 26 else { return nil }
        var buffer: UInt32 = 0
        var bits = 0
        var out = Data()
        for character in cleaned {
            guard let value = Self.alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                out.append(UInt8((buffer >> UInt32(bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        guard out.count == 16 else { return nil }
        self.bytes = out
    }

    /// "ABCD-EFGH-…-XY" (26 characters, RFC 4648 base32 without padding).
    public var formatted: String {
        var buffer: UInt32 = 0
        var bits = 0
        var characters: [Character] = []
        for byte in bytes {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                characters.append(Self.alphabet[Int((buffer >> UInt32(bits - 5)) & 31)])
                bits -= 5
            }
        }
        if bits > 0 { characters.append(Self.alphabet[Int((buffer << UInt32(5 - bits)) & 31)]) }
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }
}

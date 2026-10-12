import CryptoKit
import Foundation
import Security

/// SHA-256 of a certificate's SubjectPublicKeyInfo (SPKI), base64 — the value we pin
/// (ADR-005). Matches `openssl x509 -pubkey | openssl pkey -pubin -outform DER | sha256 | base64`.
public enum SPKIHash {
    public static func sha256Base64(of certificate: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(certificate),
              let spki = subjectPublicKeyInfo(for: key) else { return nil }
        return Data(SHA256.hash(data: spki)).base64EncodedString()
    }

    /// Rebuilds the SPKI DER around the raw key from `SecKeyCopyExternalRepresentation`
    /// (PKCS#1 for RSA, X9.63 for EC).
    static func subjectPublicKeyInfo(for key: SecKey) -> Data? {
        guard let attributes = SecKeyCopyAttributes(key) as? [String: Any],
              let type = attributes[kSecAttrKeyType as String] as? String,
              let bits = attributes[kSecAttrKeySizeInBits as String] as? Int,
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }

        let algorithm: [UInt8]
        if type == (kSecAttrKeyTypeRSA as String) {
            algorithm = DER.sequence(DER.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]) + [0x05, 0x00])
        } else if type == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            let curve: [UInt8]
            switch bits {
            case 256: curve = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]   // prime256v1
            case 384: curve = [0x2B, 0x81, 0x04, 0x00, 0x22]                     // secp384r1
            case 521: curve = [0x2B, 0x81, 0x04, 0x00, 0x23]                     // secp521r1
            default: return nil
            }
            algorithm = DER.sequence(DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]) + DER.oid(curve))
        } else {
            return nil
        }
        let bitString = DER.tlv(0x03, [0x00] + [UInt8](raw))
        return Data(DER.sequence(algorithm + bitString))
    }
}

enum DER {
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func sequence(_ content: [UInt8]) -> [UInt8] { tlv(0x30, content) }
    static func oid(_ encoded: [UInt8]) -> [UInt8] { tlv(0x06, encoded) }

    static func length(_ count: Int) -> [UInt8] {
        if count < 0x80 { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}

/// Decides whether a server trust is acceptable for our API host: the system must trust the
/// chain, and some certificate in it must match a pinned SPKI hash.
public struct PinValidator: Sendable {
    public let host: String
    public let pins: Set<String>

    public init(host: String, pins: Set<String>) {
        self.host = host
        self.pins = pins
    }

    public func evaluate(_ trust: SecTrust, host challengeHost: String) -> Bool {
        guard challengeHost == host else { return false }
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else { return false }
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        return chain.contains { certificate in
            SPKIHash.sha256Base64(of: certificate).map(pins.contains) ?? false
        }
    }
}

/// URLSession delegate that enforces `PinValidator` for the API host only.
public final class PinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let validator: PinValidator

    public init(validator: PinValidator) {
        self.validator = validator
    }

    public func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust else { return (.performDefaultHandling, nil) }
        guard space.host == validator.host else { return (.cancelAuthenticationChallenge, nil) }
        return validator.evaluate(trust, host: space.host)
            ? (.useCredential, URLCredential(trust: trust))
            : (.cancelAuthenticationChallenge, nil)
    }
}

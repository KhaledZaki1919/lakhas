import CryptoKit
import Foundation

/// LK2 request signing (ADR-027 §1). The Worker computes the same string:
///
///     "LK2\n" + METHOD + "\n" + path[?query] + "\n" + timestamp + "\n" + nonce + "\n" + deviceId
///     + "\n" + hex(SHA256(body))
///
/// signed with the device's 32-byte secret (HMAC-SHA256, base64url). Shared vectors:
/// shared/test-vectors/signing.json.
public enum RequestSigner {
    public static let version = "LK2"

    public static func canonicalString(method: String, pathAndQuery: String, timestamp: String, nonce: String,
                                       deviceId: String, body: Data) -> String {
        let bodyHash = Data(SHA256.hash(data: body)).hexString
        return [version, method.uppercased(), pathAndQuery, timestamp, nonce, deviceId, bodyHash]
            .joined(separator: "\n")
    }

    public static func signature(secret: Data, method: String, pathAndQuery: String, timestamp: String,
                                 nonce: String, deviceId: String, body: Data) -> String {
        let canonical = canonicalString(method: method, pathAndQuery: pathAndQuery, timestamp: timestamp,
                                        nonce: nonce, deviceId: deviceId, body: body)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: SymmetricKey(data: secret))
        return Data(mac).base64URLEncodedString
    }

    /// Adds the four `X-Lakhas-*` headers to `request` (its URL and body must be final).
    public static func sign(_ request: inout URLRequest, deviceId: String, secret: Data, now: Date = .now) {
        guard let url = request.url else { return }
        let timestamp = String(Int64((now.timeIntervalSince1970 * 1000).rounded()))
        let nonce = Data.random(count: 16).base64URLEncodedString
        let pathAndQuery = url.path(percentEncoded: true) + (url.query(percentEncoded: true).map { "?\($0)" } ?? "")
        let value = signature(secret: secret, method: request.httpMethod ?? "GET", pathAndQuery: pathAndQuery,
                              timestamp: timestamp, nonce: nonce, deviceId: deviceId, body: request.httpBody ?? Data())
        request.setValue(deviceId, forHTTPHeaderField: "X-Lakhas-Device")
        request.setValue(timestamp, forHTTPHeaderField: "X-Lakhas-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Lakhas-Nonce")
        request.setValue(value, forHTTPHeaderField: "X-Lakhas-Signature")
    }
}

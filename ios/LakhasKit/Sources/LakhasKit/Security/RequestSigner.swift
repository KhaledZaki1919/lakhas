import CryptoKit
import Foundation

/// Signs API requests with the device token (ADR-013). Must match the Worker byte for byte;
/// both sides are tested against shared/test-vectors/signing.json.
///
/// Canonical string:
/// `"LK1\n" + METHOD + "\n" + path[?query] + "\n" + timestamp + "\n" + nonce + "\n" + hex(SHA256(body))`
public struct RequestSigner: Sendable {
    public static let tokenIdHeader = "X-Lakhas-Token-Id"
    public static let timestampHeader = "X-Lakhas-Timestamp"
    public static let nonceHeader = "X-Lakhas-Nonce"
    public static let signatureHeader = "X-Lakhas-Signature"

    private let token: DeviceToken

    public init(token: DeviceToken) {
        self.token = token
    }

    public static func canonicalString(
        method: String, pathAndQuery: String, timestamp: String, nonce: String, body: Data
    ) -> String {
        let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return ["LK1", method.uppercased(), pathAndQuery, timestamp, nonce, bodyHash].joined(separator: "\n")
    }

    public func signature(
        method: String, pathAndQuery: String, timestamp: String, nonce: String, body: Data
    ) -> String {
        let message = Self.canonicalString(
            method: method, pathAndQuery: pathAndQuery, timestamp: timestamp, nonce: nonce, body: body
        )
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: token.secret))
        return Data(mac).base64URLEncodedString()
    }

    /// Adds the four auth headers to `request`. `now` and `nonce` are injectable for tests.
    public func sign(_ request: inout URLRequest, now: Date = .now, nonce: Data? = nil) {
        guard let url = request.url else { return }
        let timestamp = String(Int64((now.timeIntervalSince1970 * 1000).rounded(.down)))
        let nonceText = (nonce ?? Self.randomNonce()).base64URLEncodedString()
        let signature = signature(
            method: request.httpMethod ?? "GET",
            pathAndQuery: Self.pathAndQuery(of: url),
            timestamp: timestamp,
            nonce: nonceText,
            body: request.httpBody ?? Data()
        )
        request.setValue(token.tokenId, forHTTPHeaderField: Self.tokenIdHeader)
        request.setValue(timestamp, forHTTPHeaderField: Self.timestampHeader)
        request.setValue(nonceText, forHTTPHeaderField: Self.nonceHeader)
        request.setValue(signature, forHTTPHeaderField: Self.signatureHeader)
    }

    /// The path and query exactly as sent on the wire (percent-encoded), like the Worker sees them.
    static func pathAndQuery(of url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? url.path
        let query = components?.percentEncodedQuery.map { "?\($0)" } ?? ""
        return (path.isEmpty ? "/" : path) + query
    }

    static func randomNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

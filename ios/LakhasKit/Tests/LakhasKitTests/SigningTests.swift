import Foundation
import Testing
@testable import LakhasKit

/// The same vectors the Worker is tested against (shared/test-vectors/signing.json).
private struct Vectors: Decodable {
    struct Case: Decodable {
        let name: String
        let method: String
        let pathAndQuery: String
        let body: String
        let timestamp: String
        let nonce: String
        let canonical: String
        let signature: String
    }

    let token: String
    let tokenId: String
    let cases: [Case]

    static func load() throws -> Vectors {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()           // LakhasKitTests
            .deletingLastPathComponent()           // Tests
            .deletingLastPathComponent()           // LakhasKit
            .deletingLastPathComponent()           // ios
            .deletingLastPathComponent()           // repo root
            .appendingPathComponent("shared/test-vectors/signing.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }
}

struct DeviceTokenTests {
    @Test func parsesAndFormatsTheVectorToken() throws {
        let vectors = try Vectors.load()
        let token = try #require(DeviceToken(vectors.token))
        #expect(token.tokenId == vectors.tokenId)
        #expect(token.secret == Data(0..<32))
        #expect(token.text == vectors.token)
    }

    @Test func acceptsSurroundingWhitespaceFromPaste() throws {
        let vectors = try Vectors.load()
        #expect(DeviceToken("  \(vectors.token)\n") != nil)
    }

    @Test func handlesUnderscoresInsideTheSecret() throws {
        // 0xFF bytes encode to "_" in base64url.
        let secret = Data(repeating: 0xFF, count: 32)
        let text = "lk1_AbCdEfGh1234_\(secret.base64URLEncodedString())"
        let token = try #require(DeviceToken(text))
        #expect(token.secret == secret)
    }

    @Test(arguments: ["", "lk1_short_x", "lk2_AbCdEfGh1234_AAAA", "lk1_AbCd-fGh1234_AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"])
    func rejectsMalformedTokens(_ text: String) {
        #expect(DeviceToken(text) == nil)
    }
}

struct RequestSignerTests {
    @Test func matchesEverySharedVector() throws {
        let vectors = try Vectors.load()
        let signer = RequestSigner(token: try #require(DeviceToken(vectors.token)))
        for vector in vectors.cases {
            let body = Data(vector.body.utf8)
            let canonical = RequestSigner.canonicalString(
                method: vector.method, pathAndQuery: vector.pathAndQuery,
                timestamp: vector.timestamp, nonce: vector.nonce, body: body
            )
            #expect(canonical == vector.canonical, "\(vector.name)")
            #expect(
                signer.signature(
                    method: vector.method, pathAndQuery: vector.pathAndQuery,
                    timestamp: vector.timestamp, nonce: vector.nonce, body: body
                ) == vector.signature,
                "\(vector.name)"
            )
        }
    }

    @Test func signsAURLRequestWithAllHeaders() throws {
        let vectors = try Vectors.load()
        let vector = try #require(vectors.cases.first { $0.method == "GET" && $0.pathAndQuery.contains("?") })
        let signer = RequestSigner(token: try #require(DeviceToken(vectors.token)))

        var request = URLRequest(url: try #require(URL(string: "https://api.example.com\(vector.pathAndQuery)")))
        request.httpMethod = vector.method
        let now = Date(timeIntervalSince1970: try #require(Double(vector.timestamp)) / 1000)
        let nonce = try #require(Data(base64URLEncoded: vector.nonce))
        signer.sign(&request, now: now, nonce: nonce)

        #expect(request.value(forHTTPHeaderField: RequestSigner.tokenIdHeader) == vectors.tokenId)
        #expect(request.value(forHTTPHeaderField: RequestSigner.timestampHeader) == vector.timestamp)
        #expect(request.value(forHTTPHeaderField: RequestSigner.nonceHeader) == vector.nonce)
        #expect(request.value(forHTTPHeaderField: RequestSigner.signatureHeader) == vector.signature)
    }

    @Test func pathAndQueryKeepsPercentEncoding() throws {
        let url = try #require(URL(string: "https://x.test/v1/foods/search?q=%D9%81%D9%88%D9%84&lang=ar"))
        #expect(RequestSigner.pathAndQuery(of: url) == "/v1/foods/search?q=%D9%81%D9%88%D9%84&lang=ar")
    }
}

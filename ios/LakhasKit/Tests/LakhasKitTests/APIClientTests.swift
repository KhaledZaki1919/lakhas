import Foundation
import Testing
@testable import LakhasKit

/// Serves canned responses and records requests (no network).
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let next = Self.responses.isEmpty ? (500, "{}") : Self.responses.removeFirst()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: next.0, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct APIClientTests {
    private static let token = DeviceToken("lk1_Tk7f3c9a2b1d04e5_AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")

    private func makeClient(base: String = "https://api.lakhas.test") throws -> APIClient {
        StubProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(
            configuration: APIConfiguration(baseURL: try #require(URL(string: base)), pins: []),
            token: try #require(Self.token),
            session: URLSession(configuration: config),
            language: { "en" }
        )
    }

    private static let deviceJSON = """
    {"label":"Khaled's iPhone","serverTime":"2026-10-12T10:00:00.123Z",
     "caps":{"day":"2026-10-12","resetsAt":"2026-10-12T21:00:00.000Z",
       "caps":{"photo":{"used":1,"limit":10},"text":{"used":0,"limit":5},"recipe":{"used":0,"limit":5},
               "barcode":{"used":0,"limit":10},"correct":{"used":0,"limit":10}},
       "global":{"used":1,"limit":40}}}
    """

    @Test func decodesDeviceAndSignsTheRequest() async throws {
        StubProtocol.responses = [(200, Self.deviceJSON)]
        let device = try await makeClient().device()

        #expect(device.label == "Khaled's iPhone")
        #expect(device.caps.caps.photo.remaining == 9)
        let request = try #require(StubProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://api.lakhas.test/v1/device")
        #expect(request.value(forHTTPHeaderField: "X-Lakhas-Token-Id") == "Tk7f3c9a2b1d04e5")
        #expect(request.value(forHTTPHeaderField: "X-Lakhas-Signature")?.count == 43)
        #expect(request.value(forHTTPHeaderField: "X-App-Lang") == "en")
        #expect(request.value(forHTTPHeaderField: "X-Timezone") != nil)
    }

    @Test func mapsTheErrorEnvelope() async throws {
        StubProtocol.responses = [(401, #"{"error":{"code":"token_revoked","retryable":false,"message":"x"}}"#)]
        let client = try makeClient()
        do {
            _ = try await client.device()
            Issue.record("expected an error")
        } catch {
            #expect(error == .server(code: "token_revoked", status: 401))
            #expect(error.isAuthFailure)
        }
    }

    @Test func retriesGetOnceOnServerErrorWithAFreshNonce() async throws {
        StubProtocol.responses = [(503, "{}"), (200, Self.deviceJSON)]
        _ = try await makeClient().device()
        #expect(StubProtocol.requests.count == 2)
        let nonces = StubProtocol.requests.compactMap { $0.value(forHTTPHeaderField: "X-Lakhas-Nonce") }
        #expect(Set(nonces).count == 2)
    }

    @Test func doesNotRetryClientErrors() async throws {
        StubProtocol.responses = [(400, #"{"error":{"code":"invalid_request","retryable":false,"message":"x"}}"#)]
        await #expect(throws: APIError.server(code: "invalid_request", status: 400)) {
            _ = try await makeClient().device()
        }
        #expect(StubProtocol.requests.count == 1)
    }

    @Test func refusesPlaceholderHosts() async throws {
        await #expect(throws: APIError.notConfigured) {
            _ = try await makeClient(base: "https://api.lakhas.invalid").device()
        }
        #expect(StubProtocol.requests.isEmpty)
    }
}

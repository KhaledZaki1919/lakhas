import Foundation

/// Serves canned HTTP responses and records requests, including their bodies (no network).
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded {
        let request: URLRequest
        let body: Data
    }

    nonisolated(unsafe) static var responses: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var recorded: [Recorded] = []

    static func reset(_ responses: [(status: Int, body: String)]) {
        self.responses = responses
        recorded = []
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    /// The last request body parsed as JSON.
    static func lastJSON() -> [String: Any]? {
        guard let body = recorded.last?.body else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recorded.append(Recorded(request: request, body: Self.bodyData(of: request)))
        let next = Self.responses.isEmpty ? (500, "{}") : Self.responses.removeFirst()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: next.0, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession moves the body into a stream before it reaches URLProtocol.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

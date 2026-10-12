import Foundation

/// Where the API lives and which CA keys it may present (Info.plist: `LakhasAPIBaseURL`,
/// `LakhasPinnedSPKI`). Pins ship with each build; see docs/runbooks/pinning.md.
public struct APIConfiguration: Sendable {
    public let baseURL: URL
    public let pins: Set<String>

    public init(baseURL: URL, pins: Set<String>) {
        self.baseURL = baseURL
        self.pins = pins
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> APIConfiguration? {
        guard let text = bundle.object(forInfoDictionaryKey: "LakhasAPIBaseURL") as? String,
              let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        let pins = bundle.object(forInfoDictionaryKey: "LakhasPinnedSPKI") as? [String] ?? []
        return APIConfiguration(baseURL: url, pins: Set(pins))
    }

    /// True until a real API domain is configured (placeholder hosts end in `.invalid`).
    public var isPlaceholder: Bool { baseURL.host?.hasSuffix(".invalid") ?? true }
}

public enum APIError: Error, Equatable, Sendable {
    /// The server answered with the standard error envelope (codes mirror openapi.yaml).
    case server(code: String, status: Int)
    /// Network failure, TLS/pinning rejection, timeout.
    case transport
    case invalidResponse
    case notConfigured

    public var isAuthFailure: Bool {
        if case .server(let code, _) = self { return ["unauthorized", "token_revoked", "bad_signature"].contains(code) }
        return false
    }
}

/// Signed, pinned client for the Lakhas API (ADR-005, ADR-013).
public final class APIClient: Sendable {
    private let configuration: APIConfiguration
    private let signer: RequestSigner
    private let session: URLSession
    private let language: @Sendable () -> String

    public init(
        configuration: APIConfiguration,
        token: DeviceToken,
        session: URLSession? = nil,
        language: @escaping @Sendable () -> String = { APIClient.currentLanguage() }
    ) {
        self.configuration = configuration
        self.signer = RequestSigner(token: token)
        self.language = language
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.waitsForConnectivity = false
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
            let host = configuration.baseURL.host ?? ""
            self.session = URLSession(
                configuration: config,
                delegate: PinningDelegate(validator: PinValidator(host: host, pins: configuration.pins)),
                delegateQueue: nil
            )
        }
    }

    public static func currentLanguage() -> String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "ar"
    }

    // MARK: Endpoints

    public func device() async throws(APIError) -> DeviceInfo {
        try await send("GET", "/v1/device")
    }

    public func quota() async throws(APIError) -> CapStatus {
        try await send("GET", "/v1/quota")
    }

    // MARK: Transport

    public func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws(APIError) -> Response {
        let data = try await perform(method, path, query: query, body: body)
        do {
            return try JSONDecoder.lakhas.decode(Response.self, from: data)
        } catch {
            throw .invalidResponse
        }
    }

    private func perform(_ method: String, _ path: String, query: [URLQueryItem], body: Data?) async throws(APIError) -> Data {
        guard !configuration.isPlaceholder else { throw .notConfigured }
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw .notConfigured
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw .notConfigured }

        // Idempotent requests get one retry on transport errors and 5xx; each attempt is
        // re-signed with a fresh nonce.
        let attempts = method == "GET" ? 2 : 1
        var lastError = APIError.transport
        for attempt in 1...attempts {
            let request = makeRequest(url: url, method: method, body: body)

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                if (200..<300).contains(http.statusCode) { return data }
                let code = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.code ?? "internal"
                lastError = .server(code: code, status: http.statusCode)
                if http.statusCode < 500 || attempt == attempts { throw lastError }
            } catch let error as APIError {
                throw error
            } catch {
                lastError = .transport
                if attempt == attempts { throw lastError }
            }
        }
        throw lastError
    }
}

extension APIClient {
    /// A fully signed request; called per attempt so each retry gets a fresh nonce.
    fileprivate func makeRequest(url: URL, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue(language(), forHTTPHeaderField: "X-App-Lang")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")
        request.setValue(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                         forHTTPHeaderField: "X-App-Version")
        signer.sign(&request)
        return request
    }
}

private struct ErrorEnvelope: Decodable {
    struct Body: Decodable { let code: String }
    let error: Body
}

extension JSONDecoder {
    /// The Worker sends ISO 8601 with milliseconds (`toISOString()`), which `.iso8601` rejects.
    static var lakhas: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(text)"))
        }
        return decoder
    }
}

import Foundation

/// Errors from our Worker, in a form the UI can turn into its own copy.
public enum ServerError: Error, Equatable, Sendable {
    /// No connection, DNS, TLS, or a timeout: server features wait, the rest of the app works.
    case offline
    /// The Worker's error code (`invalid_credentials`, `invalid_invite`, `rate_limited`, …).
    case api(code: String, status: Int)
    /// The phone has no session (signed out).
    case notSignedIn
    /// A response we couldn't read.
    case badResponse
    /// The password or recovery code doesn't open the backup key (ADR-027 §2).
    case keyMismatch

    public var code: String? {
        if case .api(let code, _) = self { return code }
        return nil
    }
}

extension Notification.Name {
    /// Posted when the server signs this phone out (revoked device, disabled or deleted account).
    public static let lakhasSignedOut = Notification.Name("lakhas.signedOut")
}

/// Talks to `lakhas-api` (ADR-027). Public routes go out as plain JSON; signed routes carry the
/// LK2 signature; session routes add the access token, refreshing it once when it expired.
/// Never used for AI: the server has no AI routes.
public actor ServerClient {
    public enum Auth: Sendable {
        case none, signed, session
    }

    public let baseURL: URL
    private let urlSession: URLSession
    private let store: SessionStore
    private let language: @Sendable () -> String
    private var refreshing: Task<StoredSession, Error>?

    public init(baseURL: URL = ServerConfig.baseURL, urlSession: URLSession = ServerConfig.urlSession(),
                store: SessionStore = SessionStore(),
                language: @escaping @Sendable () -> String = { AppFormat.current.language }) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.store = store
        self.language = language
    }

    public func send<Response: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil,
                                          auth: Auth = .session, as type: Response.Type = Response.self) async throws -> Response {
        let bodyData = try body.map { try JSONEncoder().encode(AnyEncodable($0)) }
        do {
            return try await perform(method, path, body: bodyData, auth: auth)
        } catch ServerError.api(code: "session_expired", status: _) where auth == .session {
            _ = try await refreshedSession(force: true)
            return try await perform(method, path, body: bodyData, auth: auth)
        }
    }

    private func perform<Response: Decodable>(_ method: String, _ path: String, body: Data?, auth: Auth) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw ServerError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(language() == "en" ? "en" : "ar", forHTTPHeaderField: "X-App-Lang")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        if auth != .none {
            guard var session = store.session() else { throw ServerError.notSignedIn }
            if auth == .session {
                if session.needsRefresh() { session = try await refreshedSession(force: false) }
                request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            }
            guard let secret = Data(base64URL: session.deviceSecret) else { throw ServerError.notSignedIn }
            RequestSigner.sign(&request, deviceId: session.deviceId, secret: secret)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ServerError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw ServerError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.code ?? "http_\(http.statusCode)"
            if auth != .none, ["device_revoked", "account_disabled", "unauthorized"].contains(code) {
                signOutLocally()
            }
            throw ServerError.api(code: code, status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ServerError.badResponse
        }
    }

    /// One refresh at a time: concurrent callers wait for the same one (a refresh token works once).
    private func refreshedSession(force: Bool) async throws -> StoredSession {
        if let refreshing { return try await refreshing.value }
        guard let current = store.session() else { throw ServerError.notSignedIn }
        if !force, !current.needsRefresh() { return current }
        let task = Task<StoredSession, Error> {
            struct Body: Encodable { let refreshToken: String }
            let tokens: TokenResponse = try await perform("POST", "/v1/auth/refresh",
                                                          body: try JSONEncoder().encode(Body(refreshToken: current.refreshToken)),
                                                          auth: .signed)
            var updated = current
            updated.apply(tokens)
            try store.save(updated)
            return updated
        }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func signOutLocally() {
        guard store.session() != nil else { return }
        store.clear()
        NotificationCenter.default.post(name: .lakhasSignedOut, object: nil)
    }
}

/// Type-erases request bodies so `send` can take any `Encodable`.
private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// Where the Worker lives, and the URLSession for it (no cookies, no cache, short timeouts).
public enum ServerConfig {
    /// `LakhasAPIBaseURL` in Info.plist (project.yml), else the deployed Worker.
    public static var baseURL: URL {
        if let text = Bundle.main.object(forInfoDictionaryKey: "LakhasAPIBaseURL") as? String,
           let url = URL(string: text), url.scheme == "https" {
            return url
        }
        return defaultBaseURL
    }

    static let defaultBaseURL = URL(string: "https://lakhas-api.att-gad.workers.dev") ?? URL(fileURLWithPath: "/")

    /// The privacy policy in the app's language (ADR-027 §10).
    public static func privacyURL(language: String) -> URL {
        baseURL.appending(path: "privacy").appending(queryItems: [URLQueryItem(name: "lang", value: language)])
    }

    public static func termsURL(language: String) -> URL {
        baseURL.appending(path: "terms").appending(queryItems: [URLQueryItem(name: "lang", value: language)])
    }

    /// Set under `-uiTesting`: requests are answered by `UITestingServer`, never the network.
    nonisolated(unsafe) public static var uiTestingProtocol: URLProtocol.Type?

    public static func urlSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.waitsForConnectivity = false
        if let stub = uiTestingProtocol { config.protocolClasses = [stub] }
        return URLSession(configuration: config)
    }
}

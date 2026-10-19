import Foundation

/// Stands in for `lakhas-api` under `-uiTesting` (ADR-027): an in-memory account server behind a
/// URLProtocol, so UI tests never reach the network. It checks keys but not signatures. The only
/// valid invite code is `TEST-INVITE`. Never used otherwise.
public final class UITestingServer: URLProtocol, @unchecked Sendable {
    public static let inviteCode = "TEST-INVITE"

    private struct Account {
        var id: String
        var email: String
        var salts: [String: Any]
        var iterations: Int
        var authKey: String
        var recoverySalt: String
        var recoveryAuth: String
        var passwordEnvelope: [String: Any]
        var recoveryEnvelope: [String: Any]
        var shareProducts = true
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var accounts: [String: Account] = [:]
    nonisolated(unsafe) private static var tickets: [String: String] = [:]

    /// Forgets every account (each UI test launch starts signed out with no accounts).
    public static func reset() {
        lock.withLock {
            accounts = [:]
            tickets = [:]
        }
    }

    override public static func canInit(with request: URLRequest) -> Bool { true }
    override public static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        let body = Self.json(Self.bodyData(of: request))
        let path = request.url?.path ?? ""
        let (status, reply) = Self.lock.withLock { Self.route(request.httpMethod ?? "GET", path, body) }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]),
              let data = try? JSONSerialization.data(withJSONObject: reply) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}

    // MARK: Routes

    private typealias Reply = (Int, [String: Any])
    private typealias Handler = (_ email: String, _ body: [String: Any]) -> Reply

    nonisolated(unsafe) private static let handlers: [String: Handler] = [
        "POST /v1/auth/prelogin": { email, _ in UITestingServer.prelogin(email) },
        "POST /v1/auth/signup": { email, body in UITestingServer.signUp(email, body) },
        "POST /v1/auth/login": { email, body in UITestingServer.login(email, body) },
        "POST /v1/auth/refresh": { _, _ in (200, UITestingServer.tokens()) },
        "POST /v1/auth/logout": { _, _ in (200, ["ok": true]) },
        "POST /v1/auth/password": { _, body in UITestingServer.changePassword(body) },
        "POST /v1/auth/recovery/start": { email, body in UITestingServer.recoveryStart(email, body) },
        "POST /v1/auth/recovery/reset": { _, body in UITestingServer.recoveryReset(body) },
        "GET /v1/account": { _, _ in UITestingServer.accountInfo() },
        "PATCH /v1/account": { _, body in UITestingServer.shareProducts(body) },
        "DELETE /v1/account": { _, body in UITestingServer.deleteAccount(body) },
        "POST /v1/account/recovery": { _, body in UITestingServer.replaceRecovery(body) },
    ]

    private static func route(_ method: String, _ path: String, _ body: [String: Any]) -> Reply {
        let email = (body["email"] as? String)?.lowercased() ?? ""
        if method == "DELETE", path.hasPrefix("/v1/account/devices/") { return (200, ["ok": true]) }
        guard let handler = handlers["\(method) \(path)"] else { return error("not_found", 404) }
        return handler(email, body)
    }

    private static func prelogin(_ email: String) -> Reply {
        let account = accounts[email]
        return (200, [
            "kdf": ["name": "pbkdf2-sha256", "iterations": account?.iterations ?? AccountKeys.defaultIterations],
            "salts": account?.salts ?? ["kdf": decoy, "auth": decoy, "enc": decoy],
            "recoverySalt": account?.recoverySalt ?? decoy,
        ])
    }

    private static func signUp(_ email: String, _ body: [String: Any]) -> Reply {
        guard (body["inviteCode"] as? String)?.uppercased() == inviteCode else { return error("invalid_invite", 403) }
        guard accounts[email] == nil else { return error("email_taken", 409) }
        let recovery = body["recovery"] as? [String: Any]
        let envelopes = body["envelopes"] as? [String: Any]
        let kdf = body["kdf"] as? [String: Any]
        let account = Account(
            id: UUID().uuidString, email: email, salts: body["salts"] as? [String: Any] ?? [:],
            iterations: kdf?["iterations"] as? Int ?? AccountKeys.defaultIterations,
            authKey: body["authKey"] as? String ?? "", recoverySalt: recovery?["salt"] as? String ?? "",
            recoveryAuth: recovery?["authKey"] as? String ?? "",
            passwordEnvelope: envelopes?["password"] as? [String: Any] ?? [:],
            recoveryEnvelope: envelopes?["recovery"] as? [String: Any] ?? [:])
        accounts[email] = account
        return (201, ["user": user(account), "session": session()])
    }

    private static func login(_ email: String, _ body: [String: Any]) -> Reply {
        guard let account = accounts[email], account.authKey == body["authKey"] as? String else {
            return error("invalid_credentials", 401)
        }
        return (200, ["user": user(account), "session": session(), "keys": ["envelope": account.passwordEnvelope]])
    }

    private static func accountInfo() -> Reply {
        guard let account = accounts.values.first else { return error("unauthorized", 401) }
        let now = Int64(Date.now.timeIntervalSince1970 * 1000)
        return (200, [
            "user": ["id": account.id, "email": account.email, "createdAt": now, "shareProducts": account.shareProducts],
            "devices": [["id": "device-1", "label": "iPhone", "platform": "ios", "appVersion": "0.2.0",
                         "status": "active", "createdAt": now, "lastSeenAt": now, "current": true]],
        ])
    }

    private static func shareProducts(_ body: [String: Any]) -> Reply {
        if let share = body["shareProducts"] as? Bool, let key = accounts.first?.key {
            accounts[key]?.shareProducts = share
        }
        return (200, ["ok": true])
    }

    private static func deleteAccount(_ body: [String: Any]) -> Reply {
        guard let entry = accounts.first,
              entry.value.authKey == body["authKey"] as? String
                || entry.value.recoveryAuth == body["recoveryAuth"] as? String
        else { return error("invalid_credentials", 401) }
        accounts[entry.key] = nil
        return (200, ["ok": true])
    }

    private static func changePassword(_ body: [String: Any]) -> Reply {
        guard let key = accounts.first?.key, accounts[key]?.authKey == body["currentAuthKey"] as? String else {
            return error("invalid_credentials", 401)
        }
        accounts[key]?.authKey = body["authKey"] as? String ?? ""
        accounts[key]?.salts = body["salts"] as? [String: Any] ?? [:]
        accounts[key]?.passwordEnvelope = body["envelope"] as? [String: Any] ?? [:]
        return (200, ["ok": true])
    }

    private static func replaceRecovery(_ body: [String: Any]) -> Reply {
        guard let key = accounts.first?.key, accounts[key]?.authKey == body["authKey"] as? String else {
            return error("invalid_credentials", 401)
        }
        let recovery = body["recovery"] as? [String: Any]
        accounts[key]?.recoverySalt = recovery?["salt"] as? String ?? ""
        accounts[key]?.recoveryAuth = recovery?["authKey"] as? String ?? ""
        accounts[key]?.recoveryEnvelope = body["envelope"] as? [String: Any] ?? [:]
        return (200, ["ok": true])
    }

    private static func recoveryStart(_ email: String, _ body: [String: Any]) -> Reply {
        guard let account = accounts[email], account.recoveryAuth == body["recoveryAuth"] as? String else {
            return error("invalid_credentials", 401)
        }
        let ticket = UUID().uuidString + UUID().uuidString
        tickets[ticket] = email
        return (200, ["ticket": ticket, "envelope": account.recoveryEnvelope])
    }

    private static func recoveryReset(_ body: [String: Any]) -> Reply {
        guard let ticket = body["ticket"] as? String, let owner = tickets.removeValue(forKey: ticket),
              var account = accounts[owner] else { return error("unauthorized", 401) }
        account.authKey = body["authKey"] as? String ?? ""
        account.salts = body["salts"] as? [String: Any] ?? [:]
        account.passwordEnvelope = body["envelope"] as? [String: Any] ?? [:]
        accounts[owner] = account
        return (200, ["user": user(account), "session": session()])
    }

    private static let decoy = Data(repeating: 7, count: 16).base64URLEncodedString

    private static func user(_ account: Account) -> [String: Any] { ["id": account.id, "email": account.email] }

    private static func tokens() -> [String: Any] {
        let later = Int64(Date.now.addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        return ["accessToken": "v1.test.\(UUID().uuidString)", "accessExpiresAt": later,
                "refreshToken": "rt_\(UUID().uuidString)", "refreshExpiresAt": later]
    }

    private static func session() -> [String: Any] {
        tokens().merging(["deviceId": "device-1", "deviceSecret": Data.random(count: 32).base64URLEncodedString]) { first, _ in first }
    }

    private static func error(_ code: String, _ status: Int) -> (Int, [String: Any]) {
        (status, ["error": ["code": code, "retryable": false, "message": code]])
    }

    private static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

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

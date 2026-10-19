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

    private static func route(_ method: String, _ path: String, _ body: [String: Any]) -> (Int, [String: Any]) {
        let email = (body["email"] as? String)?.lowercased() ?? ""
        switch (method, path) {
        case ("POST", "/v1/auth/prelogin"):
            let account = accounts[email]
            return (200, [
                "kdf": ["name": "pbkdf2-sha256", "iterations": account?.iterations ?? AccountKeys.defaultIterations],
                "salts": account?.salts ?? ["kdf": decoy, "auth": decoy, "enc": decoy],
                "recoverySalt": account?.recoverySalt ?? decoy,
            ])
        case ("POST", "/v1/auth/signup"):
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
        case ("POST", "/v1/auth/login"):
            guard let account = accounts[email], account.authKey == body["authKey"] as? String else {
                return error("invalid_credentials", 401)
            }
            return (200, ["user": user(account), "session": session(), "keys": ["envelope": account.passwordEnvelope]])
        case ("POST", "/v1/auth/refresh"):
            return (200, tokens())
        case ("POST", "/v1/auth/logout"), ("PATCH", "/v1/account"), ("DELETE", _) where path.hasPrefix("/v1/account/devices/"):
            if method == "PATCH", let share = body["shareProducts"] as? Bool, let key = accounts.first?.key {
                accounts[key]?.shareProducts = share
            }
            return (200, ["ok": true])
        case ("GET", "/v1/account"):
            guard let account = accounts.values.first else { return error("unauthorized", 401) }
            let now = Int64(Date.now.timeIntervalSince1970 * 1000)
            return (200, [
                "user": ["id": account.id, "email": account.email, "createdAt": now, "shareProducts": account.shareProducts],
                "devices": [["id": "device-1", "label": "iPhone", "platform": "ios", "appVersion": "0.2.0",
                             "status": "active", "createdAt": now, "lastSeenAt": now, "current": true]],
            ])
        case ("DELETE", "/v1/account"):
            guard let entry = accounts.first,
                  entry.value.authKey == body["authKey"] as? String
                    || entry.value.recoveryAuth == body["recoveryAuth"] as? String
            else { return error("invalid_credentials", 401) }
            accounts[entry.key] = nil
            return (200, ["ok": true])
        case ("POST", "/v1/auth/password"):
            guard let key = accounts.first?.key, accounts[key]?.authKey == body["currentAuthKey"] as? String else {
                return error("invalid_credentials", 401)
            }
            accounts[key]?.authKey = body["authKey"] as? String ?? ""
            accounts[key]?.salts = body["salts"] as? [String: Any] ?? [:]
            accounts[key]?.passwordEnvelope = body["envelope"] as? [String: Any] ?? [:]
            return (200, ["ok": true])
        case ("POST", "/v1/account/recovery"):
            guard let key = accounts.first?.key, accounts[key]?.authKey == body["authKey"] as? String else {
                return error("invalid_credentials", 401)
            }
            let recovery = body["recovery"] as? [String: Any]
            accounts[key]?.recoverySalt = recovery?["salt"] as? String ?? ""
            accounts[key]?.recoveryAuth = recovery?["authKey"] as? String ?? ""
            accounts[key]?.recoveryEnvelope = body["envelope"] as? [String: Any] ?? [:]
            return (200, ["ok": true])
        case ("POST", "/v1/auth/recovery/start"):
            guard let account = accounts[email], account.recoveryAuth == body["recoveryAuth"] as? String else {
                return error("invalid_credentials", 401)
            }
            let ticket = UUID().uuidString + UUID().uuidString
            tickets[ticket] = email
            return (200, ["ticket": ticket, "envelope": account.recoveryEnvelope])
        case ("POST", "/v1/auth/recovery/reset"):
            guard let ticket = body["ticket"] as? String, let owner = tickets.removeValue(forKey: ticket),
                  var account = accounts[owner] else { return error("unauthorized", 401) }
            account.authKey = body["authKey"] as? String ?? ""
            account.salts = body["salts"] as? [String: Any] ?? [:]
            account.passwordEnvelope = body["envelope"] as? [String: Any] ?? [:]
            accounts[owner] = account
            return (200, ["user": user(account), "session": session()])
        default:
            return error("not_found", 404)
        }
    }

    private static let decoy = Data(repeating: 7, count: 16).base64URLEncodedString

    private static func user(_ account: Account) -> [String: Any] { ["id": account.id, "email": account.email] }

    private static func tokens() -> [String: Any] {
        let later = Int64(Date.now.addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        return ["accessToken": "v1.test.\(UUID().uuidString)", "accessExpiresAt": later,
                "refreshToken": "rt_\(UUID().uuidString)", "refreshExpiresAt": later]
    }

    private static func session() -> [String: Any] {
        tokens().merging(["deviceId": "device-1", "deviceSecret": Data.random(count: 32).base64URLEncodedString]) { a, _ in a }
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

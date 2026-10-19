import CryptoKit
import Foundation
import Testing
@testable import LakhasKit

/// shared/test-vectors/*.json, generated with Node's crypto (ADR-027).
private func vectorURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/test-vectors/\(name)")
}

struct SigningVectorTests {
    struct File: Decodable {
        struct Vector: Decodable {
            let name, method, pathAndQuery, body, timestamp, nonce, deviceId, canonical, signature: String
        }

        let secret: String
        let vectors: [Vector]
    }

    @Test func lk2MatchesTheWorker() throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: vectorURL("signing.json")))
        let secret = try #require(Data(base64URL: file.secret))
        #expect(file.vectors.count >= 4)
        for v in file.vectors {
            let body = Data(v.body.utf8)
            #expect(RequestSigner.canonicalString(method: v.method, pathAndQuery: v.pathAndQuery, timestamp: v.timestamp,
                                                  nonce: v.nonce, deviceId: v.deviceId, body: body) == v.canonical, "\(v.name)")
            #expect(RequestSigner.signature(secret: secret, method: v.method, pathAndQuery: v.pathAndQuery,
                                            timestamp: v.timestamp, nonce: v.nonce, deviceId: v.deviceId, body: body)
                    == v.signature, "\(v.name)")
        }
    }

    @Test func signAddsHeadersTheServerCanVerify() throws {
        var request = URLRequest(url: try #require(URL(string: "https://api.test/v1/account?x=1")))
        request.httpMethod = "PATCH"
        request.httpBody = Data(#"{"shareProducts":false}"#.utf8)
        let secret = Data.random(count: 32)
        RequestSigner.sign(&request, deviceId: "AAAAAAAAAAAAAAAAAAAAAA", secret: secret)
        let timestamp = try #require(request.value(forHTTPHeaderField: "X-Lakhas-Timestamp"))
        let nonce = try #require(request.value(forHTTPHeaderField: "X-Lakhas-Nonce"))
        #expect(timestamp.count == 13 && nonce.count == 22)
        let expected = RequestSigner.signature(secret: secret, method: "PATCH", pathAndQuery: "/v1/account?x=1",
                                               timestamp: timestamp, nonce: nonce, deviceId: "AAAAAAAAAAAAAAAAAAAAAA",
                                               body: request.httpBody ?? Data())
        #expect(request.value(forHTTPHeaderField: "X-Lakhas-Signature") == expected)
        #expect(request.value(forHTTPHeaderField: "X-Lakhas-Device") == "AAAAAAAAAAAAAAAAAAAAAA")
    }
}

struct AccountKeyVectorTests {
    struct File: Decodable {
        struct Vector: Decodable {
            let name, password, kdfSalt, authSalt, encSalt, stretched, authKey, passwordKEK: String
            let iterations: Int
            let recoverySalt, recoveryCodeBytes, recoveryCode, recoveryAuth, recoveryKEK, dek: String
            let passwordEnvelope, recoveryEnvelope: AccountKeys.Envelope
        }

        let vectors: [Vector]
    }

    @Test func derivationMatchesNode() throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: vectorURL("account-keys.json")))
        #expect(file.vectors.contains { $0.iterations == 600_000 })
        for v in file.vectors {
            let salts = AccountKeys.Salts(kdf: v.kdfSalt, auth: v.authSalt, enc: v.encSalt)
            let stretched = try AccountKeys.stretch(password: v.password, salt: try #require(Data(base64URL: v.kdfSalt)),
                                                    iterations: v.iterations)
            #expect(stretched.base64URLEncodedString == v.stretched, "\(v.name)")
            let keys = try AccountKeys.passwordKeys(password: v.password, salts: salts, iterations: v.iterations)
            #expect(keys.authKey.base64URLEncodedString == v.authKey, "\(v.name)")
            #expect(keys.passwordKEK.base64URLEncodedString == v.passwordKEK, "\(v.name)")
            #expect(keys.authKey != keys.passwordKEK)

            let code = try #require(RecoveryCode(bytes: try #require(Data(base64URL: v.recoveryCodeBytes))))
            #expect(code.formatted == v.recoveryCode, "\(v.name)")
            #expect(RecoveryCode(typed: v.recoveryCode) == code)
            let recovery = try AccountKeys.recoveryKeys(code: code, salt: v.recoverySalt)
            #expect(recovery.recoveryAuth.base64URLEncodedString == v.recoveryAuth)
            #expect(recovery.recoveryKEK.base64URLEncodedString == v.recoveryKEK)

            let dek = try #require(Data(base64URL: v.dek))
            let passwordNonce = try #require(Data(base64URL: v.passwordEnvelope.nonce))
            #expect(try AccountKeys.wrap(dataKey: dek, with: keys.passwordKEK, kind: .password, nonce: passwordNonce)
                    == v.passwordEnvelope)
            #expect(try AccountKeys.unwrap(v.passwordEnvelope, with: keys.passwordKEK, kind: .password) == dek)
            #expect(try AccountKeys.unwrap(v.recoveryEnvelope, with: recovery.recoveryKEK, kind: .recovery) == dek)
        }
    }

    @Test func envelopesFailWithTheWrongKeyOrKind() throws {
        let dek = AccountKeys.newDataKey()
        let kek = Data.random(count: 32)
        let envelope = try AccountKeys.wrap(dataKey: dek, with: kek, kind: .password)
        #expect(throws: AccountKeys.KeyError.wrongKey) {
            try AccountKeys.unwrap(envelope, with: Data.random(count: 32), kind: .password)
        }
        #expect(throws: AccountKeys.KeyError.wrongKey) { try AccountKeys.unwrap(envelope, with: kek, kind: .recovery) }
        #expect(throws: AccountKeys.KeyError.badEnvelope) {
            try AccountKeys.unwrap(.init(nonce: envelope.nonce, wrapped: "AAAA"), with: kek, kind: .password)
        }
    }

    @Test func recoveryCodeIsForgivingToType() throws {
        let code = RecoveryCode.generate()
        let shown = code.formatted
        #expect(shown.count == 32)   // 26 characters + 6 dashes
        #expect(shown.split(separator: "-").map(\.count) == [4, 4, 4, 4, 4, 4, 2])
        #expect(RecoveryCode(typed: shown.lowercased()) == code)
        #expect(RecoveryCode(typed: shown.replacingOccurrences(of: "-", with: " ")) == code)
        #expect(RecoveryCode(typed: shown.replacingOccurrences(of: "O", with: "0").replacingOccurrences(of: "I", with: "1")) == code)
        #expect(RecoveryCode(typed: String(shown.dropLast())) == nil)
        #expect(RecoveryCode(typed: "") == nil)
        #expect(RecoveryCode.generate() != code)
    }

    @Test func passwordsAreNormalizedBeforeStretching() throws {
        let salt = Data.random(count: 16)
        let composed = try AccountKeys.stretch(password: "caf\u{E9}", salt: salt, iterations: 1000)
        let decomposed = try AccountKeys.stretch(password: "cafe\u{301}", salt: salt, iterations: 1000)
        #expect(composed == decomposed)
    }

    @Test func base64URLRoundTrips() {
        for count in [0, 1, 2, 3, 16, 32, 48] {
            let data = Data.random(count: count)
            #expect(Data(base64URL: data.base64URLEncodedString) == data)
        }
        #expect(Data(base64URL: "a+b/") == nil)
    }
}

/// Account flows against `UITestingServer` (in-memory, no network). Serialized: the server is shared.
@Suite(.serialized)
struct AccountServiceTests {
    private func makeService() -> (AccountService, SessionStore) {
        UITestingServer.reset()
        ServerConfig.uiTestingProtocol = UITestingServer.self
        let store = SessionStore(secrets: MemorySecretStore())
        let client = ServerClient(baseURL: URL(string: "https://api.test") ?? ServerConfig.baseURL,
                                  urlSession: ServerConfig.urlSession(), store: store, language: { "en" })
        return (AccountService(client: client, store: store, iterations: 1000), store)
    }

    @Test func signUpKeepsThePasswordOnThePhoneAndStoresTheSession() async throws {
        let (service, store) = makeService()
        let code = try await service.signUp(inviteCode: " test-invite ", email: " Me@Example.com ",
                                            password: "a long passphrase", deviceLabel: "iPhone", appVersion: "0.2.0")
        let session = try #require(store.session())
        #expect(session.email == "me@example.com")
        #expect(Data(base64URL: session.deviceSecret)?.count == 32)
        #expect(store.dataKey()?.count == 32)
        #expect(code.formatted.count == 32)
        let dataKey = try #require(store.dataKey())

        await service.signOut()
        #expect(store.session() == nil && store.dataKey() == nil)

        // Signing in again opens the same backup key with the password.
        try await service.signIn(email: "me@example.com", password: "a long passphrase", deviceLabel: "iPhone", appVersion: nil)
        #expect(store.session() != nil && store.dataKey() == dataKey)
    }

    @Test func wrongPasswordOrInviteIsReported() async throws {
        let (service, store) = makeService()
        await #expect(throws: ServerError.api(code: "invalid_invite", status: 403)) {
            _ = try await service.signUp(inviteCode: "NOPE", email: "a@b.co", password: "a long passphrase",
                                         deviceLabel: "iPhone", appVersion: nil)
        }
        _ = try await service.signUp(inviteCode: UITestingServer.inviteCode, email: "a@b.co", password: "a long passphrase",
                                     deviceLabel: "iPhone", appVersion: nil)
        await service.signOut()
        await #expect(throws: ServerError.api(code: "invalid_credentials", status: 401)) {
            try await service.signIn(email: "a@b.co", password: "wrong passphrase", deviceLabel: "iPhone", appVersion: nil)
        }
        #expect(store.session() == nil)
    }

    @Test func recoveryCodeResetsThePasswordAndKeepsTheSameBackupKey() async throws {
        let (service, store) = makeService()
        let code = try await service.signUp(inviteCode: UITestingServer.inviteCode, email: "r@b.co",
                                            password: "first passphrase", deviceLabel: "iPhone", appVersion: nil)
        let dataKey = try #require(store.dataKey())
        await service.signOut()

        let typed = try #require(RecoveryCode(typed: code.formatted.lowercased()))
        try await service.resetPassword(email: "r@b.co", recoveryCode: typed, newPassword: "second passphrase",
                                        deviceLabel: "iPhone", appVersion: nil)
        #expect(store.dataKey() == dataKey)
        await service.signOut()
        try await service.signIn(email: "r@b.co", password: "second passphrase", deviceLabel: "iPhone", appVersion: nil)
        #expect(store.dataKey() == dataKey)

        // A wrong code never gets a ticket.
        await service.signOut()
        await #expect(throws: ServerError.api(code: "invalid_credentials", status: 401)) {
            try await service.resetPassword(email: "r@b.co", recoveryCode: .generate(), newPassword: "third passphrase",
                                            deviceLabel: "iPhone", appVersion: nil)
        }
    }

    @Test func changePasswordAndNewRecoveryCodeRewrapTheSameKey() async throws {
        let (service, store) = makeService()
        _ = try await service.signUp(inviteCode: UITestingServer.inviteCode, email: "c@b.co",
                                     password: "first passphrase", deviceLabel: "iPhone", appVersion: nil)
        let dataKey = try #require(store.dataKey())
        await #expect(throws: ServerError.api(code: "invalid_credentials", status: 401)) {
            try await service.changePassword(current: "not it at all", new: "second passphrase")
        }
        try await service.changePassword(current: "first passphrase", new: "second passphrase")
        let newCode = try await service.replaceRecoveryCode(password: "second passphrase")
        await service.signOut()
        try await service.resetPassword(email: "c@b.co", recoveryCode: newCode, newPassword: "third passphrase",
                                        deviceLabel: "iPhone", appVersion: nil)
        #expect(store.dataKey() == dataKey)
    }

    @Test func deletingTheAccountNeedsProofAndSignsOut() async throws {
        let (service, store) = makeService()
        let code = try await service.signUp(inviteCode: UITestingServer.inviteCode, email: "d@b.co",
                                            password: "a long passphrase", deviceLabel: "iPhone", appVersion: nil)
        await #expect(throws: ServerError.api(code: "invalid_credentials", status: 401)) {
            try await service.deleteAccount(proof: .password("wrong passphrase"))
        }
        #expect(store.session() != nil)
        try await service.deleteAccount(proof: .recoveryCode(code))
        #expect(store.session() == nil && store.dataKey() == nil)
        await #expect(throws: ServerError.api(code: "invalid_credentials", status: 401)) {
            try await service.signIn(email: "d@b.co", password: "a long passphrase", deviceLabel: "iPhone", appVersion: nil)
        }
    }
}

/// The client's own behavior: signing, refresh on `session_expired`, sign-out on revocation, offline.
@Suite(.serialized)
struct ServerClientTests {
    final class Route: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: (URLRequest, Data) -> (Int, String) = { _, _ in (500, "{}") }
        nonisolated(unsafe) static var seen: [URLRequest] = []
        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var body = Data()
            if let stream = request.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    body.append(buffer, count: read)
                }
                stream.close()
            }
            Self.seen.append(request)
            if request.url?.host == "offline.test" {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let (status, text) = Self.handler(request, request.httpBody ?? body)
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func signedInClient(host: String = "api.test", accessExpiresIn: TimeInterval = 600) throws -> (ServerClient, SessionStore) {
        let store = SessionStore(secrets: MemorySecretStore())
        let ms = { (t: TimeInterval) in Int64(Date.now.addingTimeInterval(t).timeIntervalSince1970 * 1000) }
        try store.save(StoredSession(userId: "u1", email: "me@example.com", response: SessionResponse(
            deviceId: "AAAAAAAAAAAAAAAAAAAAAA", deviceSecret: Data(repeating: 9, count: 32).base64URLEncodedString,
            accessToken: "v1.old", accessExpiresAt: ms(accessExpiresIn), refreshToken: "rt_old", refreshExpiresAt: ms(86_400))))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Route.self]
        Route.seen = []
        let client = ServerClient(baseURL: try #require(URL(string: "https://\(host)")), urlSession: URLSession(configuration: config),
                                  store: store, language: { "ar" })
        return (client, store)
    }

    private static let account = #"{"user":{"id":"u1","email":"me@example.com","createdAt":1,"shareProducts":true},"devices":[]}"#
    private static let tokens = #"{"accessToken":"v1.new","accessExpiresAt":99999999999999,"refreshToken":"rt_new","refreshExpiresAt":99999999999999}"#

    @Test func sessionRequestsAreSignedAndCarryTheToken() async throws {
        let (client, _) = try signedInClient()
        Route.handler = { _, _ in (200, Self.account) }
        let info: AccountInfo = try await client.send("GET", "/v1/account")
        #expect(info.user.email == "me@example.com")
        let request = try #require(Route.seen.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer v1.old")
        #expect(request.value(forHTTPHeaderField: "X-App-Lang") == "ar")
        let expected = RequestSigner.signature(
            secret: Data(repeating: 9, count: 32), method: "GET", pathAndQuery: "/v1/account",
            timestamp: request.value(forHTTPHeaderField: "X-Lakhas-Timestamp") ?? "",
            nonce: request.value(forHTTPHeaderField: "X-Lakhas-Nonce") ?? "", deviceId: "AAAAAAAAAAAAAAAAAAAAAA", body: Data())
        #expect(request.value(forHTTPHeaderField: "X-Lakhas-Signature") == expected)
    }

    @Test func expiredSessionRefreshesOnceAndRetries() async throws {
        let (client, store) = try signedInClient()
        Route.handler = { request, _ in
            switch (request.url?.path, request.value(forHTTPHeaderField: "Authorization")) {
            case ("/v1/auth/refresh", _): (200, Self.tokens)
            case (_, "Bearer v1.new"): (200, Self.account)
            default: (401, #"{"error":{"code":"session_expired"}}"#)
            }
        }
        let info: AccountInfo = try await client.send("GET", "/v1/account")
        #expect(info.user.id == "u1")
        #expect(Route.seen.map { $0.url?.path ?? "" } == ["/v1/account", "/v1/auth/refresh", "/v1/account"])
        #expect(store.session()?.refreshToken == "rt_new")
        #expect(Route.seen[1].value(forHTTPHeaderField: "Authorization") == nil)   // refresh is signed only
    }

    @Test func aTokenAboutToExpireIsRefreshedFirst() async throws {
        let (client, store) = try signedInClient(accessExpiresIn: 5)
        Route.handler = { request, _ in request.url?.path == "/v1/auth/refresh" ? (200, Self.tokens) : (200, Self.account) }
        let _: AccountInfo = try await client.send("GET", "/v1/account")
        #expect(Route.seen.map { $0.url?.path ?? "" } == ["/v1/auth/refresh", "/v1/account"])
        #expect(store.session()?.accessToken == "v1.new")
    }

    @Test func revokedDeviceSignsOutLocallyAndNotifies() async throws {
        let (client, store) = try signedInClient()
        Route.handler = { _, _ in (401, #"{"error":{"code":"device_revoked"}}"#) }
        let notified = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(forName: .lakhasSignedOut, object: nil, queue: nil) { _ in
            notified.set()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        await #expect(throws: ServerError.api(code: "device_revoked", status: 401)) {
            let _: AccountInfo = try await client.send("GET", "/v1/account")
        }
        #expect(store.session() == nil)
        #expect(notified.value)
    }

    @Test func noNetworkIsOfflineAndNoSessionIsNotSignedIn() async throws {
        let (client, _) = try signedInClient(host: "offline.test")
        await #expect(throws: ServerError.offline) {
            let _: AccountInfo = try await client.send("GET", "/v1/account")
        }
        let signedOut = ServerClient(baseURL: try #require(URL(string: "https://api.test")),
                                     store: SessionStore(secrets: MemorySecretStore()))
        await #expect(throws: ServerError.notSignedIn) {
            let _: AccountInfo = try await signedOut.send("GET", "/v1/account")
        }
    }
}

private final class NotificationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}

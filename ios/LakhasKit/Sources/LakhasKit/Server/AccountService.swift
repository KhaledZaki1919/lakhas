import Foundation

/// Account flows of ADR-027 §1–2, on the phone. Passwords are stretched here and never sent;
/// only `authKey` goes to the server. The backup data key is created here, stored on the server
/// only wrapped (password + recovery code), and kept in the Keychain after sign in.
public struct AccountService: Sendable {
    public let client: ServerClient
    public let store: SessionStore
    /// PBKDF2 rounds for new passwords. Existing accounts use what prelogin says.
    public let iterations: Int

    public init(client: ServerClient, store: SessionStore, iterations: Int = AccountKeys.defaultIterations) {
        self.client = client
        self.store = store
        self.iterations = iterations
    }

    public var session: StoredSession? { store.session() }
    public var isSignedIn: Bool { store.session() != nil }

    // MARK: Sign up / sign in

    /// Creates the account and signs this phone in. Returns the recovery code to show **once**.
    public func signUp(inviteCode: String, email: String, password: String, deviceLabel: String,
                       appVersion: String?) async throws -> RecoveryCode {
        let salts = AccountKeys.Salts.random()
        let iterations = iterations
        let keys = try await derive { try AccountKeys.passwordKeys(password: password, salts: salts, iterations: iterations) }
        let code = RecoveryCode.generate()
        let recoverySalt = Data.random(count: 16).base64URLEncodedString
        let recovery = try AccountKeys.recoveryKeys(code: code, salt: recoverySalt)
        let dataKey = AccountKeys.newDataKey()

        struct Body: Encodable {
            struct KDF: Encodable { let name: String; let iterations: Int }
            struct Recovery: Encodable { let salt: String; let authKey: String }
            struct Envelopes: Encodable { let password: AccountKeys.Envelope; let recovery: AccountKeys.Envelope }
            let inviteCode: String
            let email: String
            let authKey: String
            let kdf: KDF
            let salts: AccountKeys.Salts
            let recovery: Recovery
            let envelopes: Envelopes
            let device: DeviceInfo
        }
        let body = Body(
            inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines),
            email: Self.normalized(email), authKey: keys.authKey.base64URLEncodedString,
            kdf: .init(name: AccountKeys.kdfName, iterations: iterations), salts: salts,
            recovery: .init(salt: recoverySalt, authKey: recovery.recoveryAuth.base64URLEncodedString),
            envelopes: .init(password: try AccountKeys.wrap(dataKey: dataKey, with: keys.passwordKEK, kind: .password),
                             recovery: try AccountKeys.wrap(dataKey: dataKey, with: recovery.recoveryKEK, kind: .recovery)),
            device: DeviceInfo(label: deviceLabel, appVersion: appVersion))
        let response: SignupResponse = try await client.send("POST", "/v1/auth/signup", body: body, auth: .none)
        try store.save(StoredSession(userId: response.user.id, email: response.user.email, response: response.session))
        try store.saveDataKey(dataKey)
        return code
    }

    public func signIn(email: String, password: String, deviceLabel: String, appVersion: String?) async throws {
        let address = Self.normalized(email)
        let prelogin = try await self.prelogin(address)
        let keys = try await derive {
            try AccountKeys.passwordKeys(password: password, salts: prelogin.salts, iterations: prelogin.kdf.iterations)
        }
        struct Body: Encodable { let email: String; let authKey: String; let device: DeviceInfo }
        let response: LoginResponse = try await client.send(
            "POST", "/v1/auth/login",
            body: Body(email: address, authKey: keys.authKey.base64URLEncodedString,
                       device: DeviceInfo(label: deviceLabel, appVersion: appVersion)),
            auth: .none)
        try store.save(StoredSession(userId: response.user.id, email: response.user.email, response: response.session))
        if let envelope = response.keys.envelope {
            do {
                try store.saveDataKey(AccountKeys.unwrap(envelope, with: keys.passwordKEK, kind: .password))
            } catch {
                // The server accepted the password but the key doesn't open: never keep half a session.
                store.clear()
                throw ServerError.keyMismatch
            }
        }
    }

    /// Forgot the password: the recovery code opens the backup key and sets a new password.
    /// Every other device is signed out; this one is signed in.
    public func resetPassword(email: String, recoveryCode: RecoveryCode, newPassword: String, deviceLabel: String,
                              appVersion: String?) async throws {
        let address = Self.normalized(email)
        let prelogin = try await self.prelogin(address)
        let recovery = try AccountKeys.recoveryKeys(code: recoveryCode, salt: prelogin.recoverySalt)
        struct StartBody: Encodable { let email: String; let recoveryAuth: String }
        let start: RecoveryStartResponse = try await client.send(
            "POST", "/v1/auth/recovery/start",
            body: StartBody(email: address, recoveryAuth: recovery.recoveryAuth.base64URLEncodedString), auth: .none)
        guard let envelope = start.envelope else { throw ServerError.keyMismatch }
        let dataKey: Data
        do {
            dataKey = try AccountKeys.unwrap(envelope, with: recovery.recoveryKEK, kind: .recovery)
        } catch {
            throw ServerError.keyMismatch
        }
        let salts = AccountKeys.Salts.random()
        let iterations = iterations
        let keys = try await derive { try AccountKeys.passwordKeys(password: newPassword, salts: salts, iterations: iterations) }
        struct ResetBody: Encodable {
            struct KDF: Encodable { let name: String; let iterations: Int }
            let ticket: String
            let authKey: String
            let kdf: KDF
            let salts: AccountKeys.Salts
            let envelope: AccountKeys.Envelope
            let device: DeviceInfo
        }
        let response: ResetResponse = try await client.send(
            "POST", "/v1/auth/recovery/reset",
            body: ResetBody(ticket: start.ticket, authKey: keys.authKey.base64URLEncodedString,
                            kdf: .init(name: AccountKeys.kdfName, iterations: iterations), salts: salts,
                            envelope: try AccountKeys.wrap(dataKey: dataKey, with: keys.passwordKEK, kind: .password),
                            device: DeviceInfo(label: deviceLabel, appVersion: appVersion)),
            auth: .none)
        try store.save(StoredSession(userId: response.user.id, email: response.user.email, response: response.session))
        try store.saveDataKey(dataKey)
    }

    /// Signs this phone out. The server is told when it can be reached; locally it always happens.
    public func signOut() async {
        _ = try? await client.send("POST", "/v1/auth/logout", body: [String: String](), as: OKResponse.self)
        store.clear()
    }

    // MARK: Signed in

    public func account() async throws -> AccountInfo {
        try await client.send("GET", "/v1/account")
    }

    public func setShareProducts(_ share: Bool) async throws {
        struct Body: Encodable { let shareProducts: Bool }
        _ = try await client.send("PATCH", "/v1/account", body: Body(shareProducts: share), as: OKResponse.self)
    }

    public func signOutDevice(id: String) async throws {
        _ = try await client.send("DELETE", "/v1/account/devices/\(id)", body: [String: String](), as: OKResponse.self)
    }

    /// Keeps this device signed in and signs out the others. The backup key is re-wrapped.
    public func changePassword(current: String, new: String) async throws {
        guard let session = store.session() else { throw ServerError.notSignedIn }
        guard let dataKey = store.dataKey() else { throw ServerError.keyMismatch }
        let prelogin = try await self.prelogin(session.email)
        let currentKeys = try await derive {
            try AccountKeys.passwordKeys(password: current, salts: prelogin.salts, iterations: prelogin.kdf.iterations)
        }
        let salts = AccountKeys.Salts.random()
        let iterations = iterations
        let newKeys = try await derive { try AccountKeys.passwordKeys(password: new, salts: salts, iterations: iterations) }
        struct Body: Encodable {
            struct KDF: Encodable { let name: String; let iterations: Int }
            let currentAuthKey: String
            let authKey: String
            let kdf: KDF
            let salts: AccountKeys.Salts
            let envelope: AccountKeys.Envelope
        }
        _ = try await client.send(
            "POST", "/v1/auth/password",
            body: Body(currentAuthKey: currentKeys.authKey.base64URLEncodedString,
                       authKey: newKeys.authKey.base64URLEncodedString,
                       kdf: .init(name: AccountKeys.kdfName, iterations: iterations), salts: salts,
                       envelope: try AccountKeys.wrap(dataKey: dataKey, with: newKeys.passwordKEK, kind: .password)),
            as: OKResponse.self)
    }

    /// A new recovery code (the old one stops working). Needs the password. Show it **once**.
    public func replaceRecoveryCode(password: String) async throws -> RecoveryCode {
        guard let session = store.session() else { throw ServerError.notSignedIn }
        guard let dataKey = store.dataKey() else { throw ServerError.keyMismatch }
        let prelogin = try await self.prelogin(session.email)
        let keys = try await derive {
            try AccountKeys.passwordKeys(password: password, salts: prelogin.salts, iterations: prelogin.kdf.iterations)
        }
        let code = RecoveryCode.generate()
        let salt = Data.random(count: 16).base64URLEncodedString
        let recovery = try AccountKeys.recoveryKeys(code: code, salt: salt)
        struct Body: Encodable {
            struct Recovery: Encodable { let salt: String; let authKey: String }
            let authKey: String
            let recovery: Recovery
            let envelope: AccountKeys.Envelope
        }
        _ = try await client.send(
            "POST", "/v1/account/recovery",
            body: Body(authKey: keys.authKey.base64URLEncodedString,
                       recovery: .init(salt: salt, authKey: recovery.recoveryAuth.base64URLEncodedString),
                       envelope: try AccountKeys.wrap(dataKey: dataKey, with: recovery.recoveryKEK, kind: .recovery)),
            as: OKResponse.self)
        return code
    }

    public enum DeletionProof: Sendable {
        case password(String)
        case recoveryCode(RecoveryCode)
    }

    /// Deletes the account and everything the server holds for it, then signs out (App Store 5.1.1(v)).
    public func deleteAccount(proof: DeletionProof) async throws {
        guard let session = store.session() else { throw ServerError.notSignedIn }
        let prelogin = try await self.prelogin(session.email)
        let body: [String: String]
        switch proof {
        case .password(let password):
            let keys = try await derive {
                try AccountKeys.passwordKeys(password: password, salts: prelogin.salts, iterations: prelogin.kdf.iterations)
            }
            body = ["authKey": keys.authKey.base64URLEncodedString]
        case .recoveryCode(let code):
            let keys = try AccountKeys.recoveryKeys(code: code, salt: prelogin.recoverySalt)
            body = ["recoveryAuth": keys.recoveryAuth.base64URLEncodedString]
        }
        _ = try await client.send("DELETE", "/v1/account", body: body, as: OKResponse.self)
        store.clear()
    }

    // MARK: Helpers

    func prelogin(_ email: String) async throws -> PreloginResponse {
        struct Body: Encodable { let email: String }
        let response: PreloginResponse = try await client.send("POST", "/v1/auth/prelogin", body: Body(email: email), auth: .none)
        guard response.kdf.name == AccountKeys.kdfName else { throw ServerError.badResponse }
        return response
    }

    /// PBKDF2 at 600,000 rounds takes a moment: never on the main thread.
    private func derive<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    public static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

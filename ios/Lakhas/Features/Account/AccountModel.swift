import Foundation
import LakhasKit
import Observation
import SwiftUI
import UIKit

/// The optional account (ADR-027) for the screens: who's signed in, and the flows. Under
/// `-uiTesting` it talks to `UITestingServer` and keeps secrets in memory.
@MainActor
@Observable
final class AccountModel {
    private let service: AccountService
    private(set) var session: StoredSession?
    private(set) var info: AccountInfo?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(uiTesting: Bool = ProcessInfo.processInfo.arguments.contains("-uiTesting")) {
        let store = uiTesting ? SessionStore(secrets: MemorySecretStore()) : SessionStore()
        service = AccountService(client: ServerClient(store: store), store: store)
        session = store.session()
        observer = NotificationCenter.default.addObserver(forName: .lakhasSignedOut, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var isSignedIn: Bool { session != nil }

    func reload() {
        session = service.session
        if session == nil { info = nil }
    }

    // MARK: Flows (each one reloads the session afterwards)

    func signUp(inviteCode: String, email: String, password: String) async throws -> RecoveryCode {
        defer { reload() }
        return try await service.signUp(inviteCode: inviteCode, email: email, password: password,
                                        deviceLabel: Self.deviceLabel, appVersion: Self.appVersion)
    }

    func signIn(email: String, password: String) async throws {
        defer { reload() }
        try await service.signIn(email: email, password: password, deviceLabel: Self.deviceLabel, appVersion: Self.appVersion)
    }

    func resetPassword(email: String, code: RecoveryCode, newPassword: String) async throws {
        defer { reload() }
        try await service.resetPassword(email: email, recoveryCode: code, newPassword: newPassword,
                                        deviceLabel: Self.deviceLabel, appVersion: Self.appVersion)
    }

    func signOut() async {
        await service.signOut()
        reload()
    }

    func loadInfo() async throws {
        defer { reload() }
        info = try await service.account()
    }

    func setShareProducts(_ share: Bool) async throws {
        try await service.setShareProducts(share)
        try await loadInfo()
    }

    func signOutDevice(_ device: AccountInfo.Device) async throws {
        try await service.signOutDevice(id: device.id)
        try await loadInfo()
    }

    func changePassword(current: String, new: String) async throws {
        try await service.changePassword(current: current, new: new)
    }

    func newRecoveryCode(password: String) async throws -> RecoveryCode {
        try await service.replaceRecoveryCode(password: password)
    }

    func deleteAccount(proof: AccountService.DeletionProof) async throws {
        defer { reload() }
        try await service.deleteAccount(proof: proof)
    }

    // MARK: Device facts sent at sign in (shown in the device list)

    static var deviceLabel: String { UIDevice.current.model }

    static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

/// Server errors in the user's words (never the raw code).
enum AccountErrorText {
    static func key(for error: Error) -> LocalizedStringKey {
        switch error as? ServerError {
        case .offline: "account.error.offline"
        case .notSignedIn: "account.error.signedOut"
        case .keyMismatch: "account.error.keyMismatch"
        case .badResponse, .none: "account.error.generic"
        case .api(let code, _):
            switch code {
            case "invalid_credentials": "account.error.credentials"
            case "invalid_invite": "account.error.invite"
            case "email_taken": "account.error.emailTaken"
            case "too_many_attempts", "rate_limited": "account.error.tooMany"
            case "account_disabled": "account.error.disabled"
            case "device_revoked", "unauthorized": "account.error.signedOut"
            case "stale_request": "account.error.clock"
            case "quota_exceeded": "account.error.quota"
            case "invalid_request": "account.error.invalid"
            default: "account.error.generic"
            }
        }
    }
}

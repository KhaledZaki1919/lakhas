import LakhasKit
import Observation
import SwiftUI

/// App-wide session state: nothing that talks to the server works until a device token is
/// verified (PROJECT_PROMPT.md §4.1, ADR-013).
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case needsToken
        /// The token is stored and was accepted by the server.
        case ready(DeviceToken)
        /// No API domain in this build yet (placeholder URL): the app runs without the server.
        case offline
    }

    private(set) var phase: Phase
    let configuration: APIConfiguration?
    private let tokenStore: TokenStore

    init(tokenStore: TokenStore = TokenStore(), configuration: APIConfiguration? = .fromBundle()) {
        self.tokenStore = tokenStore
        self.configuration = configuration
        phase = tokenStore.load().map(Phase.ready) ?? .needsToken
    }

    var isServerConfigured: Bool { configuration.map { !$0.isPlaceholder } ?? false }

    var token: DeviceToken? {
        if case .ready(let token) = phase { return token }
        return nil
    }

    func client() -> APIClient? {
        guard let configuration, let token else { return nil }
        return APIClient(configuration: configuration, token: token)
    }

    /// Verifies the pasted or scanned token with `GET /v1/device`, then stores it.
    func activate(_ text: String) async -> TokenEntryError? {
        guard let token = DeviceToken(text) else { return .format }
        guard let configuration else { return .notConfigured }
        do {
            _ = try await APIClient(configuration: configuration, token: token).device()
        } catch {
            return TokenEntryError(error)
        }
        do {
            try tokenStore.save(token)
        } catch {
            return .generic
        }
        phase = .ready(token)
        return nil
    }

    func continueOffline() {
        guard !isServerConfigured else { return }
        phase = .offline
    }

    /// Called on `token_revoked` / `unauthorized`, or from Settings → Replace token. Local data stays.
    func forgetToken() {
        tokenStore.clear()
        phase = .needsToken
    }
}

enum TokenEntryError: Equatable {
    case format, invalid, clock, rateLimited, network, notConfigured, generic

    init(_ error: APIError) {
        switch error {
        case .server(let code, _) where ["unauthorized", "token_revoked", "bad_signature"].contains(code):
            self = .invalid
        case .server("stale_request", _):
            self = .clock
        case .server("rate_limited", _):
            self = .rateLimited
        case .transport:
            self = .network
        case .notConfigured:
            self = .notConfigured
        default:
            self = .generic
        }
    }

    var messageKey: LocalizedStringKey {
        switch self {
        case .format: "token.error.format"
        case .invalid: "token.error.invalid"
        case .clock: "token.error.clock"
        case .rateLimited: "token.error.rateLimited"
        case .network: "token.error.network"
        case .notConfigured: "token.error.notConfigured"
        case .generic: "token.error.generic"
        }
    }
}

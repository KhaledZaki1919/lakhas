import Foundation
import SwiftData
import Testing
@testable import LakhasKit

/// Accepts requests and never answers, like a server that holds the connection open.
private final class HangingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var started: [URLRequest] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingProtocol.self]
        return URLSession(configuration: config)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.started.append(request) }
    override func stopLoading() {}
}

private let aqKey = "AQ.Ab8RN6JzT1yQ-example_key-0123456789xyz"

struct AIKeyTests {
    @Test func sanitizerRemovesInvisibleAndWrappingCharacters() {
        #expect(AIKeyStore.sanitize("  \(aqKey)\n") == aqKey)
        #expect(AIKeyStore.sanitize("\u{200F}\(aqKey)\u{200B}\u{200E}") == aqKey)            // RTL/LTR marks, zero-width space
        #expect(AIKeyStore.sanitize("\u{FEFF}AIzaSyA12345\u{2066}67890\u{2069}abcdefghijk") == "AIzaSyA1234567890abcdefghijk")
        #expect(AIKeyStore.sanitize("\"\(aqKey)\"") == aqKey)
        #expect(AIKeyStore.sanitize("“\(aqKey)”") == aqKey)
        #expect(AIKeyStore.sanitize("Bearer \(aqKey)") == aqKey)
        #expect(AIKeyStore.sanitize("AQ.ab\u{00A0}cd\tef\r\ngh") == "AQ.abcdefgh")
        #expect(AIKeyStore.sanitize(" \u{200F} ").isEmpty)
    }

    @Test func maskedShowsFirstFourLastFourAndLength() {
        #expect(AIKeyStore.masked(aqKey) == "AQ.A…9xyz · \(aqKey.count)")
    }

    @Test func bothGeminiFormatsAreAcceptedWithoutWarnings() {
        #expect(AIKeyStore.warnings(for: aqKey, provider: .gemini).isEmpty)
        #expect(AIKeyStore.warnings(for: "AIzaSyA1234567890abcdefghijklmnop", provider: .gemini).isEmpty)
    }

    @Test func mismatchedProviderIsFlagged() {
        #expect(AIKeyStore.warnings(for: "sk-ant-api03-abcdefghijklmnopqrstuv", provider: .gemini) == [.looksLike(.anthropic)])
        #expect(AIKeyStore.warnings(for: "sk-or-v1-abcdefghijklmnopqrstuvwxyz", provider: .openai) == [.looksLike(.openrouter)])
        #expect(AIKeyStore.warnings(for: aqKey, provider: .anthropic) == [.looksLike(.gemini)])
        #expect(AIKeyStore.warnings(for: "sk-proj-abcdefghijklmnopqrstuvwxyz", provider: .openai).isEmpty)
    }

    @Test func unknownFormatsAndOddCharactersOnlyWarn() {
        #expect(AIKeyStore.warnings(for: "ya29.abcdefghijklmnopqrstuvwxyz", provider: .gemini) == [.unexpectedFormat])
        #expect(AIKeyStore.warnings(for: "AQ.abc", provider: .gemini) == [.tooShort])
        #expect(AIKeyStore.warnings(for: "AQ.abcdefghijklmnopqrstu\u{200F}\u{064A}", provider: .gemini).contains(.unexpectedCharacters))
        #expect(AIKeyStore.warnings(for: "", provider: .gemini).isEmpty)
    }
}

struct AIDeadlineTests {
    @Test func returnsTheValueWhenTheOperationFinishes() async throws {
        let value = try await AIDeadline.run(seconds: 5) { 42 }
        #expect(value == 42)
    }

    @Test func anAwaitThatNeverReturnsTimesOut() async {
        let started = Date()
        await #expect(throws: AIError.timedOut) {
            _ = try await AIDeadline.run(seconds: 0.3) {
                await withUnsafeContinuation { (_: UnsafeContinuation<Int, Never>) in }   // never resumed
            }
        }
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func cancellingTheCallerReturnsCancelled() async {
        let task = Task {
            try await AIDeadline.run(seconds: 30) {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                return 1
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let result = await task.result
        #expect(throws: AIError.cancelled) { try result.get() }
    }

    @Test func operationErrorsPassThrough() async {
        await #expect(throws: AIError.invalidKey) {
            _ = try await AIDeadline.run(seconds: 5) { () async throws -> Int in throw AIError.invalidKey }
        }
    }
}

@Suite(.serialized)
@MainActor
struct AIServiceDeadlineTests {
    private func makeService() throws -> (AIService, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "deadline-\(UUID().uuidString)"))
        let context = ModelContext(try LakhasStore.makeContainer(inMemory: true))
        let service = AIService(context: context, defaults: defaults, session: HangingProtocol.session())
        service.testTimeout = 0.5
        return (service, defaults)
    }

    @Test func testConnectionTimeoutStopsLoadingAndIsRecorded() async throws {
        HangingProtocol.started = []
        let (service, defaults) = try makeService()
        let started = Date()
        let result = await service.testConnection(provider: .gemini, key: " \u{200F}\(aqKey)\n", model: "gemini-flash-latest")

        #expect(Date().timeIntervalSince(started) < 5)   // the spinner stops: the call returned
        guard case .failure(.timedOut) = result else {
            Issue.record("expected a timeout, got \(result)")
            return
        }
        // The key went in the header only, already cleaned.
        let sent = try #require(HangingProtocol.started.first)
        #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == aqKey)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.url?.query?.contains("key") != true)

        let diagnostic = try #require(AIDiagnosticsStore.load(from: defaults))
        #expect(diagnostic.failedStep == .timeout)
        #expect(diagnostic.feature == .connectionTest)
        #expect(diagnostic.endpoint == "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent")
        // The abandoned request ends with a cancellation error; it must not replace the timeout.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(AIDiagnosticsStore.load(from: defaults)?.failedStep == .timeout)
        #expect(!(AIDiagnosticsStore.load(from: defaults)?.report().contains(aqKey) ?? true))
    }

    @Test func cancellingTheTestReturnsCancelledAndIsRecorded() async throws {
        let (service, defaults) = try makeService()
        service.testTimeout = 30
        let task = Task { await service.testConnection(provider: .gemini, key: aqKey, model: "gemini-flash-latest") }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let result = await task.value
        guard case .failure(.cancelled) = result else {
            Issue.record("expected cancellation, got \(result)")
            return
        }
        #expect(AIDiagnosticsStore.load(from: defaults)?.failedStep == .cancelled)
    }

    @Test func modelListTimesOutToAnEmptyList() async throws {
        let (service, _) = try makeService()
        let started = Date()
        let models = await service.listModels(provider: .gemini, key: aqKey)
        #expect(models.isEmpty)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

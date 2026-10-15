import Foundation
import SwiftData

/// The app's single entry point to AI (ADR-020): checks the key and the optional daily limit,
/// picks the model for the feature, runs `StructuredAI`, and records usage + estimated cost.
/// There is no fallback: without a key every call throws `AIError.noKey`.
///
/// Every call has a hard deadline (`AIDeadline`), so no path can leave a spinner running:
/// success, provider error, timeout and cancellation all return, and all leave a "Last AI
/// request" diagnostic.
@MainActor
public final class AIService {
    private let context: ModelContext
    private let keyStore: AIKeyStore
    private let defaults: UserDefaults
    private let session: URLSession

    /// Settings → AI "Test connection" and the model list.
    public var testTimeout: TimeInterval = 30
    /// Photo, text, label and recipe analysis (the per-request URL timeout is 180 s).
    public var analysisTimeout: TimeInterval = 200

    public init(context: ModelContext, keyStore: AIKeyStore = AIKeyStore(),
                defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.context = context
        self.keyStore = keyStore
        self.defaults = defaults
        self.session = session
    }

    /// UI tests only: when set, requests go to this provider and no key is required.
    public nonisolated(unsafe) static var overrideProvider: AIProvider?

    public var settings: AISettings { AISettings.load(from: defaults) }

    public var hasKey: Bool { Self.overrideProvider != nil || keyStore.hasKey(for: settings.provider) }

    /// Requests made today (connection tests excluded).
    public func requestsToday(now: Date = .now) -> Int {
        let today = DayKey.make(now)
        let test = AIFeature.connectionTest.rawValue
        let descriptor = FetchDescriptor<UsageRecord>(predicate: #Predicate { $0.dayKey == today && $0.featureRaw != test })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    public func summary(since start: Date) -> UsageSummary {
        let descriptor = FetchDescriptor<UsageRecord>(predicate: #Predicate { $0.date >= start })
        return UsageSummary((try? context.fetch(descriptor)) ?? [])
    }

    /// Runs a structured request for `feature`, enforcing key presence and the daily limit.
    public func run<Value: Decodable & AIValidatable>(
        _ type: Value.Type, request: AIRequest, feature: AIFeature
    ) async throws -> StructuredResult<Value> {
        let settings = settings
        let provider: AIProvider
        var secrets: [String] = []
        if let override = Self.overrideProvider {
            provider = override
        } else {
            guard let key = keyStore.key(for: settings.provider) else { throw AIError.noKey }
            provider = settings.provider.makeProvider(apiKey: key, session: session)
            secrets = [key]
        }
        if feature != .connectionTest, let limit = settings.dailyLimit, requestsToday() >= limit {
            throw AIError.dailyLimitReached
        }
        return try await guarded(type, request: request, feature: feature, provider: provider,
                                 model: settings.model(for: feature), secrets: secrets, seconds: analysisTimeout)
    }

    /// Settings → AI "Test connection" with the given provider/key/model (before saving them).
    /// Returns within `testTimeout`; cancelling the calling task returns `.cancelled`.
    public func testConnection(
        provider: AIProviderKind, key: String, model: String
    ) async -> Result<StructuredResult<ConnectionTest.Reply>, AIError> {
        let clean = AIKeyStore.sanitize(key)
        do {
            return .success(try await guarded(
                ConnectionTest.Reply.self, request: ConnectionTest.request, feature: .connectionTest,
                provider: provider.makeProvider(apiKey: clean, session: session), model: model,
                secrets: [clean, key], seconds: testTimeout
            ))
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    /// The provider's live model list, or [] on any failure or after `testTimeout`.
    public func listModels(provider: AIProviderKind, key: String) async -> [String] {
        let client = provider.makeProvider(apiKey: AIKeyStore.sanitize(key), session: session)
        return (try? await AIDeadline.run(seconds: testTimeout) { try await client.listModels() }) ?? []
    }

    /// `StructuredAI` under a deadline. A timeout or cancellation writes its own diagnostic and
    /// silences the abandoned run, so a late answer can't overwrite it.
    private func guarded<Value: Decodable & AIValidatable>(
        _ type: Value.Type, request: AIRequest, feature: AIFeature, provider: AIProvider, model: String,
        secrets: [String], seconds: TimeInterval
    ) async throws -> StructuredResult<Value> {
        let latch = DiagnosticLatch(UncheckedDefaults(defaults))
        let trace = AITrace()
        let started = Date()
        let ai = StructuredAI(
            provider: provider,
            model: model,
            secrets: secrets,
            onDiagnostic: { latch.save($0) },
            onUsage: { [weak self] event in
                Task { @MainActor in self?.record(event) }
            }
        )
        do {
            return try await AIDeadline.run(seconds: seconds) {
                try await ai.run(type, request: request, feature: feature, trace: trace)
            }
        } catch let error as AIError where error == .timedOut || error == .cancelled {
            let timedOut = error == .timedOut
            latch.close(with: AIDiagnostic(
                date: started,
                provider: provider.kind,
                model: model,
                feature: feature,
                endpoint: trace.endpoint.map { AIRedactor.redact($0, secrets: secrets) },
                httpStatus: trace.status,
                failedStep: timedOut ? .timeout : .cancelled,
                attempts: 1,
                durationMs: Int(Date().timeIntervalSince(started) * 1000),
                message: timedOut ? "No answer within \(Int(seconds)) s" : "Cancelled",
                errorBody: nil,
                replyExcerpt: nil
            ))
            throw error
        }
    }

    func record(_ event: AIUsageEvent) {
        let cost = PriceTable.estimatedCost(of: event.usage, model: event.model, overrides: PriceTable.overrides(from: defaults))
        context.insert(UsageRecord(event: event, estimatedCost: cost))
        try? context.save()
    }
}

/// UserDefaults is thread-safe but not marked Sendable.
private struct UncheckedDefaults: @unchecked Sendable {
    let value: UserDefaults
    init(_ value: UserDefaults) { self.value = value }
}

/// Saves diagnostics until a timeout/cancellation closes it with its own.
private final class DiagnosticLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private let defaults: UncheckedDefaults

    init(_ defaults: UncheckedDefaults) {
        self.defaults = defaults
    }

    func save(_ diagnostic: AIDiagnostic) {
        lock.withLock {
            guard !closed else { return }
            AIDiagnosticsStore.save(diagnostic, to: defaults.value)
        }
    }

    func close(with diagnostic: AIDiagnostic) {
        lock.withLock {
            closed = true
            AIDiagnosticsStore.save(diagnostic, to: defaults.value)
        }
    }
}

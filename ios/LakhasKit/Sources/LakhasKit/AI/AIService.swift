import Foundation
import SwiftData

/// The app's single entry point to AI (ADR-020): checks the key and the optional daily limit,
/// picks the model for the feature, runs `StructuredAI`, and records usage + estimated cost.
/// There is no fallback: without a key every call throws `AIError.noKey`.
@MainActor
public final class AIService {
    private let context: ModelContext
    private let keyStore: AIKeyStore
    private let defaults: UserDefaults
    private let session: URLSession

    public init(context: ModelContext, keyStore: AIKeyStore = AIKeyStore(),
                defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.context = context
        self.keyStore = keyStore
        self.defaults = defaults
        self.session = session
    }

    public var settings: AISettings { AISettings.load(from: defaults) }

    public var hasKey: Bool { keyStore.hasKey(for: settings.provider) }

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
        guard let key = keyStore.key(for: settings.provider) else { throw AIError.noKey }
        if feature != .connectionTest, let limit = settings.dailyLimit, requestsToday() >= limit {
            throw AIError.dailyLimitReached
        }
        let ai = StructuredAI(
            provider: settings.provider.makeProvider(apiKey: key, session: session),
            model: settings.model(for: feature),
            onUsage: { [weak self] event in
                Task { @MainActor in self?.record(event) }
            }
        )
        return try await ai.run(type, request: request, feature: feature)
    }

    /// Settings → AI "Test connection" with the given provider/key/model (before saving them).
    public func testConnection(
        provider: AIProviderKind, key: String, model: String
    ) async -> Result<StructuredResult<ConnectionTest.Reply>, AIError> {
        let ai = StructuredAI(
            provider: provider.makeProvider(apiKey: key, session: session),
            model: model,
            onUsage: { [weak self] event in
                Task { @MainActor in self?.record(event) }
            }
        )
        do {
            return .success(try await ai.run(ConnectionTest.Reply.self, request: ConnectionTest.request, feature: .connectionTest))
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    public func listModels(provider: AIProviderKind, key: String) async -> [String] {
        (try? await provider.makeProvider(apiKey: key, session: session).listModels()) ?? []
    }

    func record(_ event: AIUsageEvent) {
        let cost = PriceTable.estimatedCost(of: event.usage, model: event.model, overrides: PriceTable.overrides(from: defaults))
        context.insert(UsageRecord(event: event, estimatedCost: cost))
        try? context.save()
    }
}

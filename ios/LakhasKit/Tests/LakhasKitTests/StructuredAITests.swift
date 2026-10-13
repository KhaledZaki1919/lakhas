import Foundation
import Testing
@testable import LakhasKit

/// Scripted provider: returns the queued results in order and records the requests.
private final class FakeProvider: AIProvider, @unchecked Sendable {
    let kind: AIProviderKind
    var results: [Result<String, AIError>]
    var requests: [(request: AIRequest, structured: Bool)] = []

    init(kind: AIProviderKind = .anthropic, results: [Result<String, AIError>]) {
        self.kind = kind
        self.results = results
    }

    func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse {
        requests.append((request, structured))
        let next = results.isEmpty ? .failure(.network) : results.removeFirst()
        switch next {
        case .success(let text): return AIResponse(text: text, usage: AIUsage(inputTokens: 100, outputTokens: 10), model: model)
        case .failure(let error): throw error
        }
    }

    func listModels() async throws -> [String] { [] }
}

private struct Meal: Decodable, AIValidatable {
    let name: String
    let grams: Double

    func validate() throws {
        guard grams > 0, grams < 5000 else { throw AIValidationError("grams out of range") }
    }
}

private final class Events: @unchecked Sendable {
    var list: [AIUsageEvent] = []
}

private let request = AIRequest(
    system: "sys",
    userText: "meal",
    schema: JSONSchema.object(["name": JSONSchema.string, "grams": JSONSchema.number])
)

struct StructuredAITests {
    @Test func decodesValidJSONOnTheFirstTry() async throws {
        let provider = FakeProvider(results: [.success(#"{"name":"كشري","grams":450}"#)])
        let events = Events()
        let ai = StructuredAI(provider: provider, model: "m") { events.list.append($0) }
        let result = try await ai.run(Meal.self, request: request, feature: .text)
        #expect(result.value.name == "كشري")
        #expect(result.attempts == 1)
        #expect(events.list.map(\.success) == [true])
    }

    @Test func retriesOnceWithTheProblemAppended() async throws {
        let provider = FakeProvider(results: [.success(#"{"name":"x","grams":-1}"#), .success(#"{"name":"x","grams":120}"#)])
        let events = Events()
        let ai = StructuredAI(provider: provider, model: "m") { events.list.append($0) }
        let result = try await ai.run(Meal.self, request: request, feature: .photo)
        #expect(result.attempts == 2)
        #expect(provider.requests.last?.request.userText.contains("grams out of range") == true)
        #expect(events.list.map(\.success) == [false, true])   // both calls cost tokens
    }

    @Test func givesUpAfterTheRetry() async {
        let provider = FakeProvider(results: [.success("not json"), .success(#"{"name":"x"}"#)])
        let ai = StructuredAI(provider: provider, model: "m")
        await #expect(throws: AIError.invalidOutput(#"missing field "grams""#)) {
            _ = try await ai.run(Meal.self, request: request, feature: .text)
        }
        #expect(provider.requests.count == 2)
    }

    @Test func acceptsCodeFencesAndStrayText() async throws {
        let provider = FakeProvider(results: [.success("Here it is:\n```json\n{\"name\":\"foul\",\"grams\":200}\n```")])
        let result = try await StructuredAI(provider: provider, model: "m").run(Meal.self, request: request, feature: .text)
        #expect(result.value.grams == 200)
    }

    @Test func fallsBackToPromptOnlyJSONWhenTheSchemaIsRejected() async throws {
        let provider = FakeProvider(kind: .openrouter, results: [
            .failure(.badRequest("response_format json_schema is not supported by this model")),
            .success(#"{"name":"x","grams":50}"#),
        ])
        let result = try await StructuredAI(provider: provider, model: "m").run(Meal.self, request: request, feature: .text)
        #expect(result.attempts == 1)
        #expect(provider.requests.map(\.structured) == [true, false])
        #expect(provider.requests.last?.request.system.contains("JSON Schema") == true)
    }

    @Test func geminiAlwaysGetsTheSchemaInThePrompt() async throws {
        let provider = FakeProvider(kind: .gemini, results: [.success(#"{"name":"x","grams":50}"#)])
        _ = try await StructuredAI(provider: provider, model: "m").run(Meal.self, request: request, feature: .text)
        #expect(provider.requests.first?.structured == false)
        #expect(provider.requests.first?.request.system.contains("\"additionalProperties\":false") == true)
    }

    @Test func providerErrorsPassThroughAndAreRecorded() async {
        let provider = FakeProvider(results: [.failure(.invalidKey)])
        let events = Events()
        let ai = StructuredAI(provider: provider, model: "m") { events.list.append($0) }
        await #expect(throws: AIError.invalidKey) { _ = try await ai.run(Meal.self, request: request, feature: .text) }
        #expect(events.list.count == 1)
        #expect(events.list.first?.success == false)
    }
}

struct AISettingsAndPriceTests {
    @Test func highAccuracyOnlyAffectsPhotoAnalysis() {
        var settings = AISettings(provider: .anthropic, highAccuracy: true)
        #expect(settings.model(for: .photo) == "claude-sonnet-5-5")
        #expect(settings.model(for: .text) == "claude-haiku-5-5")
        #expect(settings.model(for: .correction) == "claude-haiku-5-5")
        settings.highAccuracy = false
        #expect(settings.model(for: .photo) == "claude-haiku-5-5")
    }

    @Test func customModelsOverrideRecommendations() {
        let settings = AISettings(provider: .openai, standardModels: ["openai": "my-mini"], accurateModels: [:], highAccuracy: true)
        #expect(settings.model(for: .text) == "my-mini")
        #expect(settings.model(for: .photo) == AIProviderKind.openai.recommendedAccurateModel)
    }

    @Test func settingsRoundTripThroughUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "AISettingsTests-\(UUID().uuidString)"))
        let settings = AISettings(provider: .gemini, highAccuracy: true, dailyLimit: 20)
        settings.save(to: defaults)
        #expect(AISettings.load(from: defaults) == settings)
    }

    @Test func estimatesCostFromTokens() throws {
        // Haiku 5.5: 2,000 in × $0.10/M + 500 out × $0.50/M = $0.00045
        let cost = try #require(PriceTable.estimatedCost(of: AIUsage(inputTokens: 2000, outputTokens: 500), model: "claude-haiku-5-5"))
        #expect(abs(cost - 0.00045) < 1e-12)
    }

    @Test func matchesOpenRouterNamesAndUserOverrides() {
        #expect(PriceTable.price(for: "anthropic/claude-sonnet-5.5") == PriceTable.builtIn["claude-sonnet-5-5"])
        let custom = ModelPrice(inputPerMillion: 0.3, outputPerMillion: 2.5)
        #expect(PriceTable.price(for: "gpt-5-mini") == nil)
        #expect(PriceTable.price(for: "gpt-5-mini", overrides: ["gpt-5-mini": custom]) == custom)
    }

    @Test func maskedKeysHideTheMiddle() {
        #expect(AIKeyStore.masked("sk-ant-api03-abcdefghijklmnop1234") == "sk-ant-a…1234")
        #expect(AIKeyStore.masked("short") == "•••••")
    }

    @Test func jsonSchemaObjectsAreStrict() {
        let schema = JSONSchema.object(["b": JSONSchema.number, "a": JSONSchema.string])
        #expect(schema["additionalProperties"] == false)
        #expect(schema["required"] == ["a", "b"])
    }
}

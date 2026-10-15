import Foundation
import Testing
@testable import LakhasKit

/// Holds the diagnostic a run reports.
final class DiagnosticBox: @unchecked Sendable {
    var value: AIDiagnostic?
}

private let key = "AIzaSyTESTKEY0123456789abcdefghijk"
private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"
private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x10, 0x20])

private let mealRequest = AIRequest(
    system: "You analyze meals.",
    userText: "<user_content>koshary</user_content>",
    images: [jpeg],
    schema: MealAnalysis.schema,
    schemaName: "meal_analysis",
    maxOutputTokens: 4096
)

/// Responses recorded from generativelanguage.googleapis.com (v1beta), trimmed.
private enum Recorded {
    // swiftlint:disable line_length
    static let success = #"{"candidates":[{"content":{"parts":[{"text":"{\"ok\":true}","thoughtSignature":"CiQB0e2Kb3x"}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":1290,"candidatesTokenCount":7,"totalTokenCount":1351,"thoughtsTokenCount":54},"modelVersion":"gemini-3.8-flash","responseId":"r1"}"#
    static let withThoughtPart = #"{"candidates":[{"content":{"parts":[{"text":"Looking at the plate…","thought":true},{"text":"{\"ok\":true}"}],"role":"model"},"finishReason":"STOP"}],"modelVersion":"gemini-3.8-flash"}"#
    static let schemaRejected = #"{"error":{"code":400,"message":"Invalid JSON payload received. Unknown name \"additionalProperties\" at 'generation_config.response_schema': Cannot find field.","status":"INVALID_ARGUMENT"}}"#
    static let locationUnsupported = #"{"error":{"code":400,"message":"User location is not supported for the API use.","status":"FAILED_PRECONDITION"}}"#
    static let thinkingRejected = #"{"error":{"code":400,"message":"Thinking level is not supported for this model.","status":"INVALID_ARGUMENT"}}"#
    static let invalidKey = #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key. (key: AIzaSyTESTKEY0123456789abcdefghijk)","status":"INVALID_ARGUMENT"}}"#
    static let notFound = #"{"error":{"code":404,"message":"models/gemini-pro-latest is not found for API version v1beta, or is not supported for generateContent. Call ListModels to see the list of available models and their supported methods.","status":"NOT_FOUND"}}"#
    static let quota = #"{"error":{"code":429,"message":"You exceeded your current quota, please check your plan and billing details. Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 10","status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"52s"}]}}"#
    static let maxTokens = #"{"candidates":[{"content":{"parts":[{"text":"{\"items\":[{\"nameAr\":\"كشري\",\"nameEn\":\"Kosh"}],"role":"model"},"finishReason":"MAX_TOKENS"}],"usageMetadata":{"promptTokenCount":5200,"candidatesTokenCount":10,"thoughtsTokenCount":28662}}"#
    static let cutOffJSON = #"{"candidates":[{"content":{"parts":[{"text":"{\"ok\": tr"}],"role":"model"},"finishReason":"STOP"}]}"#
    // swiftlint:enable line_length
}

private func structuredAI(model: String = "gemini-flash-latest", box: DiagnosticBox) -> StructuredAI {
    StructuredAI(provider: GeminiProvider(apiKey: key, session: StubProtocol.session()), model: model,
                 secrets: [key], onDiagnostic: { box.value = $0 })
}

private func body(_ index: Int) -> [String: Any]? {
    guard StubProtocol.recorded.indices.contains(index) else { return nil }
    return try? JSONSerialization.jsonObject(with: StubProtocol.recorded[index].body) as? [String: Any]
}

private func generationConfig(_ index: Int) -> [String: Any]? {
    body(index)?["generationConfig"] as? [String: Any]
}

/// Part of the serialized `AIProviderTests` suite: `StubProtocol` is shared state.
extension AIProviderTests {
    // MARK: Request

    @Test func geminiSendsNativeSchemaLowThinkingAndInlineJPEG() async throws {
        StubProtocol.reset([(200, Recorded.success)])
        let response = try await GeminiProvider(apiKey: key, session: StubProtocol.session())
            .complete(mealRequest, model: "gemini-flash-latest", structured: true)

        #expect(response.text == #"{"ok":true}"#)
        #expect(response.usage == AIUsage(inputTokens: 1290, outputTokens: 61))
        #expect(response.model == "gemini-3.8-flash")

        let sent = try #require(StubProtocol.recorded.first)
        #expect(sent.request.url?.absoluteString == endpoint)          // v1beta, no key in the URL
        #expect(sent.request.value(forHTTPHeaderField: "x-goog-api-key") == key)
        let config = try #require(generationConfig(0))
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["maxOutputTokens"] as? Int == 4096 + 24576)
        #expect((config["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "low")
        let schema = try #require(config["responseSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        let rawBody = String(decoding: sent.body, as: UTF8.self)
        #expect(!rawBody.contains("additionalProperties"))
        let parts = try #require(((body(0)?["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]])
        let inline = try #require(parts.first?["inlineData"] as? [String: Any])
        #expect(inline["mimeType"] as? String == "image/jpeg")
        #expect(inline["data"] as? String == jpeg.base64EncodedString())
        #expect(parts.last?["text"] as? String == mealRequest.userText)
    }

    @Test func geminiSchemaConversionUsesNullableAndDropsUnsupportedKeywords() {
        let converted = GeminiProvider.openAPISchema(MealAnalysis.schema)
        let text = converted.jsonString()
        #expect(!text.contains("additionalProperties"))
        #expect(!text.contains(#""null""#))
        #expect(converted["properties"]?["notes"] == ["type": "string", "nullable": true])
        #expect(converted["properties"]?["items"]?["items"]?["properties"]?["foodDbId"] == ["type": "string", "nullable": true])
        #expect(converted["required"] == MealAnalysis.schema["required"])
    }

    @Test func geminiThinkingSettingPerModelFamily() {
        #expect(GeminiProvider.thinking(for: "gemini-flash-latest") == .level("low"))
        #expect(GeminiProvider.thinking(for: "gemini-3.8-flash") == .level("low"))
        #expect(GeminiProvider.thinking(for: "gemini-2.5-flash") == .budget(1024))
        #expect(GeminiProvider.thinking(for: "gemini-2.5-flash-lite") == .off)
        #expect(GeminiProvider.thinking(for: "gemini-2.0-flash") == .off)
    }

    @Test func geminiSkipsThoughtParts() throws {
        let response = try GeminiProvider.parse(Data(Recorded.withThoughtPart.utf8), model: "m")
        #expect(response.text == #"{"ok":true}"#)
    }

    // MARK: Errors, with the diagnostic each one leaves

    @Test func gemini400SchemaRejectionFallsBackToThePrompt() async throws {
        StubProtocol.reset([(400, Recorded.schemaRejected), (200, Recorded.success)])
        let box = DiagnosticBox()
        let result = try await structuredAI(box: box).run(ConnectionTest.Reply.self, request: ConnectionTest.request,
                                                           feature: .connectionTest)
        #expect(result.value.ok)
        #expect(generationConfig(0)?["responseSchema"] != nil)
        #expect(generationConfig(1)?["responseSchema"] == nil)
        #expect((body(1)?["systemInstruction"] as? [String: Any]).map { "\($0)" }?.contains("JSON Schema") == true)
        #expect(box.value?.succeeded == true)
        #expect(box.value?.attempts == 2)
    }

    @Test func gemini400ShowsTheProviderMessage() async throws {
        StubProtocol.reset([(400, Recorded.locationUnsupported)])
        let box = DiagnosticBox()
        await #expect(throws: AIError.badRequest("User location is not supported for the API use.")) {
            _ = try await structuredAI(box: box).run(ConnectionTest.Reply.self, request: ConnectionTest.request,
                                                    feature: .text)
        }
        let diagnostic = try #require(box.value)
        #expect(diagnostic.failedStep == .http)
        #expect(diagnostic.httpStatus == 400)
        #expect(diagnostic.endpoint == endpoint)
        #expect(diagnostic.message == "User location is not supported for the API use.")
        #expect(diagnostic.errorBody?.contains("FAILED_PRECONDITION") == true)
        #expect(diagnostic.provider == .gemini)
        #expect(diagnostic.model == "gemini-flash-latest")
    }

    @Test func gemini400ThinkingRejectedIsResentWithoutIt() async throws {
        StubProtocol.reset([(400, Recorded.thinkingRejected), (200, Recorded.success)])
        let response = try await GeminiProvider(apiKey: key, session: StubProtocol.session())
            .complete(mealRequest, model: "gemini-flash-latest", structured: true)
        #expect(response.text == #"{"ok":true}"#)
        #expect(generationConfig(0)?["thinkingConfig"] != nil)
        #expect(generationConfig(1)?["thinkingConfig"] == nil)
        #expect(generationConfig(1)?["responseSchema"] != nil)
    }

    @Test func geminiKeyIsRedactedFromDiagnostics() async throws {
        StubProtocol.reset([(400, Recorded.invalidKey)])
        let box = DiagnosticBox()
        await #expect(throws: AIError.invalidKey) {
            _ = try await structuredAI(box: box).run(ConnectionTest.Reply.self, request: ConnectionTest.request,
                                                    feature: .connectionTest)
        }
        let report = try #require(box.value?.report())
        #expect(!report.contains(key))
        #expect(!report.contains("AIzaSy"))
        #expect(report.contains("[redacted]"))
    }

    @Test func gemini404ModelNotFound() async throws {
        StubProtocol.reset([(404, Recorded.notFound)])
        let box = DiagnosticBox()
        await #expect(throws: AIError.modelNotFound) {
            _ = try await structuredAI(model: "gemini-pro-latest", box: box)
                .run(ConnectionTest.Reply.self, request: ConnectionTest.request, feature: .photo)
        }
        #expect(box.value?.httpStatus == 404)
        #expect(box.value?.message?.contains("is not found for API version v1beta") == true)
        #expect(box.value?.endpoint?.hasSuffix("models/gemini-pro-latest:generateContent") == true)
    }

    @Test func gemini429LongWaitIsARateLimitWithoutRetry() async throws {
        StubProtocol.reset([(429, Recorded.quota)])
        let box = DiagnosticBox()
        await #expect(throws: AIError.rateLimited) {
            _ = try await structuredAI(box: box).run(ConnectionTest.Reply.self, request: ConnectionTest.request,
                                                    feature: .text)
        }
        #expect(StubProtocol.recorded.count == 1)      // 52 s is too long to wait in the app
        #expect(box.value?.httpStatus == 429)
        #expect(box.value?.message?.contains("free_tier_requests") == true)
    }

    @Test func geminiMaxTokensIsTruncatedNotAJSONError() async throws {
        StubProtocol.reset([(200, Recorded.maxTokens)])
        let box = DiagnosticBox()
        await #expect(throws: AIError.truncated) {
            _ = try await structuredAI(box: box).run(ConnectionTest.Reply.self, request: ConnectionTest.request,
                                                    feature: .photo)
        }
        #expect(StubProtocol.recorded.count == 1)
        #expect(box.value?.failedStep == .response)
        #expect(box.value?.httpStatus == 200)
        #expect(box.value?.errorBody?.contains("MAX_TOKENS") == true)
    }

    @Test func geminiCutOffJSONIsRetriedOnceThenReported() async throws {
        StubProtocol.reset([(200, Recorded.cutOffJSON), (200, Recorded.cutOffJSON)])
        let box = DiagnosticBox()
        await #expect(throws: AIError.invalidOutput("no JSON object found")) {
            _ = try await structuredAI(box: box).run(ConnectionTest.Reply.self, request: ConnectionTest.request,
                                                    feature: .text)
        }
        #expect(StubProtocol.recorded.count == 2)
        let diagnostic = try #require(box.value)
        #expect(diagnostic.failedStep == .json)
        #expect(diagnostic.attempts == 2)
        #expect(diagnostic.replyExcerpt == #"{"ok": tr"#)
    }
}

struct AIRedactorTests {
    @Test func redactsKnownKeyShapesAndQueryKeys() {
        #expect(AIRedactor.redact("bad key AIzaSyA1234567890abcdefghijklmnop") == "bad key [redacted]")
        #expect(AIRedactor.redact("sk-ant-api03-abcdefghijklmnop rejected") == "[redacted] rejected")
        #expect(AIRedactor.redact("https://x.test/v1?key=SECRET&alt=json") == "https://x.test/v1?key=[redacted]&alt=json")
        #expect(AIRedactor.redact("my secret is hunter22", secrets: ["hunter22"]) == "my secret is [redacted]")
        #expect(AIRedactor.redact("task-abcdefghijklmnop failed") == "task-abcdefghijklmnop failed")
    }
}

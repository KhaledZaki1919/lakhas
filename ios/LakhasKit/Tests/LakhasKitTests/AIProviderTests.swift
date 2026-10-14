import Foundation
import Testing
@testable import LakhasKit

private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
private let request = AIRequest(
    system: "You analyze meals.",
    userText: "<user_content>koshary</user_content>",
    images: [jpeg],
    schema: JSONSchema.object(["ok": JSONSchema.boolean]),
    schemaName: "meal",
    maxOutputTokens: 800
)

@Suite(.serialized)
struct AIProviderTests {
    // MARK: Anthropic

    @Test func anthropicBuildsAStructuredVisionRequest() async throws {
        // swiftlint:disable:next line_length
        StubProtocol.reset([(200, #"{"content":[{"type":"text","text":"{\"ok\":true}"}],"usage":{"input_tokens":1500,"output_tokens":40},"stop_reason":"end_turn","model":"claude-haiku-5-5"}"#)])
        let provider = AnthropicProvider(apiKey: "sk-ant-test", session: StubProtocol.session())
        let response = try await provider.complete(request, model: "claude-haiku-5-5", structured: true)

        #expect(response.text == #"{"ok":true}"#)
        #expect(response.usage == AIUsage(inputTokens: 1500, outputTokens: 40))
        let sent = try #require(StubProtocol.recorded.last)
        #expect(sent.request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(sent.request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(sent.request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

        let body = try #require(StubProtocol.lastJSON())
        #expect(body["max_tokens"] as? Int == 800)
        let system = try #require((body["system"] as? [[String: Any]])?.first)
        #expect(system["text"] as? String == "You analyze meals.")
        #expect((system["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
        let output = try #require(body["output_config"] as? [String: Any])
        let format = try #require(output["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(output["effort"] as? String == "low")
        let content = try #require(((body["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        #expect(content.first?["type"] as? String == "image")
        #expect(((content.first?["source"] as? [String: Any])?["data"] as? String) == jpeg.base64EncodedString())
        #expect(content.last?["text"] as? String == "<user_content>koshary</user_content>")
    }

    @Test func anthropicOmitsEffortAndFormatWhenNotWanted() throws {
        let body = AnthropicProvider(apiKey: "k").body(for: request, model: "claude-3-haiku-20240307", structured: false)
        #expect(body["output_config"] == nil)
    }

    @Test func anthropicRefusalIsReported() async {
        StubProtocol.reset([(200, #"{"content":[],"stop_reason":"refusal"}"#)])
        let provider = AnthropicProvider(apiKey: "k", session: StubProtocol.session())
        await #expect(throws: AIError.refused) {
            _ = try await provider.complete(request, model: "claude-haiku-5-5", structured: true)
        }
    }

    // MARK: OpenAI / OpenRouter

    @Test func openAIUsesStrictJSONSchemaAndDataURLImages() async throws {
        // swiftlint:disable:next line_length
        StubProtocol.reset([(200, #"{"choices":[{"message":{"content":"{\"ok\":true}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":900,"completion_tokens":20},"model":"gpt-5-mini"}"#)])
        let provider = OpenAICompatibleProvider(kind: .openai, apiKey: "sk-test", session: StubProtocol.session())
        let response = try await provider.complete(request, model: "gpt-5-mini", structured: true)

        #expect(response.usage == AIUsage(inputTokens: 900, outputTokens: 20))
        let sent = try #require(StubProtocol.recorded.last)
        #expect(sent.request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try #require(StubProtocol.lastJSON())
        #expect(body["max_completion_tokens"] as? Int == 800)
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect((format["json_schema"] as? [String: Any])?["strict"] as? Bool == true)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "system")
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        let url = (parts.last?["image_url"] as? [String: Any])?["url"] as? String
        #expect(url == "data:image/jpeg;base64,\(jpeg.base64EncodedString())")
    }

    @Test func openRouterUsesItsEndpointAndClassicTokenLimit() async throws {
        StubProtocol.reset([(200, #"{"choices":[{"message":{"content":"{}"},"finish_reason":"stop"}]}"#)])
        let provider = OpenAICompatibleProvider(kind: .openrouter, apiKey: "sk-or-test", session: StubProtocol.session())
        _ = try await provider.complete(request, model: "google/gemini-flash-latest", structured: true)
        let sent = try #require(StubProtocol.recorded.last)
        #expect(sent.request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(sent.request.value(forHTTPHeaderField: "X-Title") == "Lakhas")
        let body = try #require(StubProtocol.lastJSON())
        #expect(body["max_tokens"] as? Int == 800)
        #expect(body["max_completion_tokens"] == nil)
    }

    // MARK: Gemini

    @Test func geminiUsesJSONModeAndInlineImages() async throws {
        // swiftlint:disable:next line_length
        StubProtocol.reset([(200, #"{"candidates":[{"content":{"parts":[{"text":"{\"ok\":true}"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":700,"candidatesTokenCount":15,"thoughtsTokenCount":100}}"#)])
        let provider = GeminiProvider(apiKey: "AIza-test", session: StubProtocol.session())
        let response = try await provider.complete(request, model: "gemini-flash-latest", structured: false)

        #expect(response.usage == AIUsage(inputTokens: 700, outputTokens: 115))
        let sent = try #require(StubProtocol.recorded.last)
        #expect(sent.request.url?.absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent")
        #expect(sent.request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")
        let body = try #require(StubProtocol.lastJSON())
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["maxOutputTokens"] as? Int == 800 + 8192)   // room for thinking
        let parts = try #require(((body["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]])
        #expect((parts.first?["inlineData"] as? [String: Any])?["mimeType"] as? String == "image/jpeg")
    }

    @Test func geminiLegacyModelsKeepTheRequestedLimit() {
        #expect(GeminiProvider.outputTokenLimit(request, model: "gemini-2.0-flash") == 800)
    }

    @Test func geminiRetriesOnceAfterAShortRateLimit() async throws {
        // swiftlint:disable:next line_length
        let limited = #"{"error":{"code":429,"message":"You exceeded your current quota, please check your plan and billing details.","status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"0s"}]}}"#
        StubProtocol.reset([(429, limited), (200, #"{"candidates":[{"content":{"parts":[{"text":"{}"}]},"finishReason":"STOP"}]}"#)])
        let provider = GeminiProvider(apiKey: "k", session: StubProtocol.session())
        let response = try await provider.complete(request, model: "gemini-flash-latest", structured: false)
        #expect(response.text == "{}")
        #expect(StubProtocol.recorded.count == 2)
    }

    @Test func retryDelayOnlyForShortWaits() {
        // swiftlint:disable:next line_length
        let body = { (delay: String) in Data(#"{"error":{"status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"#(delay)"}]}}"#.utf8) }
        #expect(AIHTTP.retryDelay(status: 429, body: body("17s")) == 17.5)
        #expect(AIHTTP.retryDelay(status: 429, body: body("3600s")) == nil)
        #expect(AIHTTP.retryDelay(status: 429, body: Data(#"{"error":{"message":"Rate limit reached"}}"#.utf8)) == nil)
        #expect(AIHTTP.retryDelay(status: 503, body: Data()) == 2)
        #expect(AIHTTP.retryDelay(status: 400, body: Data()) == nil)
    }

    // MARK: Errors

    @Test(arguments: [
        (401, #"{"error":{"message":"invalid x-api-key"}}"#, AIError.invalidKey),
        (400, #"{"error":{"message":"API key not valid. Please pass a valid API key."}}"#, .invalidKey),
        (400, #"{"error":{"message":"Your credit balance is too low"}}"#, .insufficientCredit),
        (429, #"{"error":{"message":"You exceeded your current quota"}}"#, .insufficientCredit),
        (429, #"{"error":{"message":"Rate limit reached"}}"#, .rateLimited),
        (429, #"{"error":{"message":"You exceeded your current quota","status":"RESOURCE_EXHAUSTED"}}"#, .rateLimited),
        (404, #"{"error":{"message":"model: nope"}}"#, .modelNotFound),
        (529, #"{"error":{"message":"Overloaded"}}"#, .providerUnavailable),
    ])
    func mapsProviderErrors(status: Int, body: String, expected: AIError) {
        #expect(AIHTTP.mapError(status: status, body: Data(body.utf8)) == expected)
    }

    @Test func providerListsSaySoForEveryKind() {
        for kind in AIProviderKind.allCases {
            #expect(kind.builtInModels.contains(kind.recommendedStandardModel))
            #expect(kind.keyPageURL?.scheme == "https")
        }
    }
}

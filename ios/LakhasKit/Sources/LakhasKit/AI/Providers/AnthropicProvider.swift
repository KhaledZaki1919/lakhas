import Foundation

/// Anthropic Messages API, called directly with the user's key (ADR-020).
/// Structured output: `output_config.format = {type: "json_schema", schema}`.
public struct AnthropicProvider: AIProvider {
    public let kind = AIProviderKind.anthropic
    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://api.anthropic.com/v1"

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private var headers: [String: String] {
        ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
    }

    /// Effort control exists on the Claude 4.6+ generation; older models reject it.
    static func supportsEffort(_ model: String) -> Bool {
        ["claude-haiku-5", "claude-sonnet-5", "claude-opus-5", "claude-fable-5",
         "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8", "claude-sonnet-4-6"].contains { model.hasPrefix($0) }
    }

    func body(for request: AIRequest, model: String, structured: Bool) -> JSONValue {
        var content: [JSONValue] = request.images.map { jpeg in
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": .string(jpeg.base64EncodedString())]]
        }
        content.append(["type": "text", "text": .string(request.userText)])

        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .int(request.maxOutputTokens),
            "system": .string(request.system),
            "messages": [["role": "user", "content": .array(content)]],
        ]
        var outputConfig: [String: JSONValue] = [:]
        if structured { outputConfig["format"] = ["type": "json_schema", "schema": request.schema] }
        if Self.supportsEffort(model) { outputConfig["effort"] = "low" }
        if !outputConfig.isEmpty { body["output_config"] = .object(outputConfig) }
        return .object(body)
    }

    public func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse {
        guard let url = URL(string: "\(baseURL)/messages") else { throw AIError.network }
        let urlRequest = try AIHTTP.jsonRequest(url: url, headers: headers, body: body(for: request, model: model, structured: structured))
        let data = try await AIHTTP.send(urlRequest, session: session)
        return try Self.parse(data, model: model)
    }

    struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        struct Usage: Decodable {
            let inputTokens: Int
            let outputTokens: Int
        }

        let content: [Block]
        let usage: Usage?
        let stopReason: String?
        let model: String?
    }

    static func parse(_ data: Data, model: String) throws -> AIResponse {
        guard let response = try? AIHTTP.snakeCaseDecoder.decode(MessagesResponse.self, from: data) else {
            throw AIError.invalidOutput("unreadable response")
        }
        if response.stopReason == "refusal" { throw AIError.refused }
        let text = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        if text.isEmpty { throw response.stopReason == "max_tokens" ? AIError.truncated : AIError.invalidOutput("empty reply") }
        return AIResponse(
            text: text,
            usage: response.usage.map { AIUsage(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens) },
            model: response.model ?? model
        )
    }

    public func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/models?limit=100") else { return [] }
        let data = try await AIHTTP.send(AIHTTP.getRequest(url: url, headers: headers), session: session)
        struct List: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        return (try? JSONDecoder().decode(List.self, from: data))?.data.map(\.id) ?? []
    }
}

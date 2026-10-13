import Foundation

/// OpenAI Chat Completions, also used for OpenRouter (same request format) — ADR-020.
/// Structured output: `response_format = {type: "json_schema", json_schema: {name, strict, schema}}`.
public struct OpenAICompatibleProvider: AIProvider {
    public let kind: AIProviderKind
    private let apiKey: String
    private let session: URLSession

    public init(kind: AIProviderKind, apiKey: String, session: URLSession = .shared) {
        precondition(kind == .openai || kind == .openrouter, "OpenAI-compatible providers only")
        self.kind = kind
        self.apiKey = apiKey
        self.session = session
    }

    private var baseURL: String {
        kind == .openrouter ? "https://openrouter.ai/api/v1" : "https://api.openai.com/v1"
    }

    private var headers: [String: String] {
        var headers = ["Authorization": "Bearer \(apiKey)"]
        if kind == .openrouter { headers["X-Title"] = "Lakhas" }
        return headers
    }

    func body(for request: AIRequest, model: String, structured: Bool) -> JSONValue {
        var userContent: [JSONValue] = [["type": "text", "text": .string(request.userText)]]
        userContent += request.images.map { jpeg in
            ["type": "image_url", "image_url": ["url": .string("data:image/jpeg;base64,\(jpeg.base64EncodedString())")]]
        }
        var body: [String: JSONValue] = [
            "model": .string(model),
            "messages": [
                ["role": "system", "content": .string(request.system)],
                ["role": "user", "content": .array(userContent)],
            ],
        ]
        // OpenAI renamed the limit for current models; OpenRouter keeps the classic name.
        body[kind == .openai ? "max_completion_tokens" : "max_tokens"] = .int(request.maxOutputTokens)
        if structured {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": .string(request.schemaName), "strict": true, "schema": request.schema],
            ]
        }
        return .object(body)
    }

    public func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse {
        guard let url = URL(string: "\(baseURL)/chat/completions") else { throw AIError.network }
        let urlRequest = try AIHTTP.jsonRequest(url: url, headers: headers, body: body(for: request, model: model, structured: structured))
        let data = try await AIHTTP.send(urlRequest, session: session)
        return try Self.parse(data, model: model)
    }

    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let refusal: String?
            }

            let message: Message
            let finish_reason: String?
        }

        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }

        let choices: [Choice]
        let usage: Usage?
        let model: String?
    }

    static func parse(_ data: Data, model: String) throws -> AIResponse {
        guard let response = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let choice = response.choices.first else {
            throw AIError.invalidOutput("unreadable response")
        }
        if let refusal = choice.message.refusal, !refusal.isEmpty { throw AIError.refused }
        let text = choice.message.content ?? ""
        if text.isEmpty { throw choice.finish_reason == "length" ? AIError.truncated : AIError.invalidOutput("empty reply") }
        return AIResponse(
            text: text,
            usage: response.usage.map { AIUsage(inputTokens: $0.prompt_tokens, outputTokens: $0.completion_tokens) },
            model: response.model ?? model
        )
    }

    public func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/models") else { return [] }
        let data = try await AIHTTP.send(AIHTTP.getRequest(url: url, headers: headers), session: session)
        struct List: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let ids = (try? JSONDecoder().decode(List.self, from: data))?.data.map(\.id) ?? []
        guard kind == .openai else { return ids.sorted() }
        // OpenAI also lists embedding, audio and image models; keep the chat families.
        return ids.filter { $0.hasPrefix("gpt") || $0.hasPrefix("o") || $0.hasPrefix("chatgpt") }.sorted()
    }
}

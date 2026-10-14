import Foundation

/// Google Gemini `generateContent`, called directly with the user's key (ADR-020).
/// JSON mode (`responseMimeType: application/json`); the schema goes in the prompt and every
/// answer is validated by `StructuredAI`.
public struct GeminiProvider: AIProvider {
    public let kind = AIProviderKind.gemini
    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private var headers: [String: String] { ["x-goog-api-key": apiKey] }

    static func modelPath(_ model: String) -> String {
        model.hasPrefix("models/") ? model : "models/\(model)"
    }

    /// Thinking models (2.5 and later) count thoughts against `maxOutputTokens`, so they get extra
    /// room or a long think can cut the JSON off. Older models reject limits above 8192.
    static func outputTokenLimit(_ request: AIRequest, model: String) -> Int {
        let legacy = ["gemini-1.", "gemini-2.0"].contains { model.contains($0) }
        return legacy ? request.maxOutputTokens : request.maxOutputTokens + 8192
    }

    func body(for request: AIRequest, model: String) -> JSONValue {
        var parts: [JSONValue] = request.images.map { jpeg in
            ["inlineData": ["mimeType": "image/jpeg", "data": .string(jpeg.base64EncodedString())]]
        }
        parts.append(["text": .string(request.userText)])
        return [
            "systemInstruction": ["parts": [["text": .string(request.system)]]],
            "contents": [["role": "user", "parts": .array(parts)]],
            "generationConfig": ["responseMimeType": "application/json", "maxOutputTokens": .int(Self.outputTokenLimit(request, model: model))],
        ]
    }

    public func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse {
        guard let url = URL(string: "\(baseURL)/\(Self.modelPath(model)):generateContent") else { throw AIError.modelNotFound }
        let urlRequest = try AIHTTP.jsonRequest(url: url, headers: headers, body: body(for: request, model: model))
        let data = try await AIHTTP.send(urlRequest, session: session, retryTransient: true)
        return try Self.parse(data, model: model)
    }

    struct GenerateResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }

            let content: Content?
            let finishReason: String?
        }

        struct Feedback: Decodable { let blockReason: String? }

        struct Usage: Decodable {
            let promptTokenCount: Int?
            let candidatesTokenCount: Int?
            let thoughtsTokenCount: Int?
        }

        let candidates: [Candidate]?
        let promptFeedback: Feedback?
        let usageMetadata: Usage?
        let modelVersion: String?
    }

    static func parse(_ data: Data, model: String) throws -> AIResponse {
        guard let response = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw AIError.invalidOutput("unreadable response")
        }
        if response.promptFeedback?.blockReason != nil { throw AIError.refused }
        let candidate = response.candidates?.first
        if candidate?.finishReason == "SAFETY" || candidate?.finishReason == "PROHIBITED_CONTENT" { throw AIError.refused }
        let text = candidate?.content?.parts?.compactMap(\.text).joined() ?? ""
        if text.isEmpty { throw candidate?.finishReason == "MAX_TOKENS" ? AIError.truncated : AIError.invalidOutput("empty reply") }
        // Thinking tokens are billed as output.
        let usage = response.usageMetadata.map {
            AIUsage(inputTokens: $0.promptTokenCount ?? 0,
                    outputTokens: ($0.candidatesTokenCount ?? 0) + ($0.thoughtsTokenCount ?? 0))
        }
        return AIResponse(text: text, usage: usage, model: response.modelVersion ?? model)
    }

    public func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/models?pageSize=200") else { return [] }
        let data = try await AIHTTP.send(AIHTTP.getRequest(url: url, headers: headers), session: session)
        struct List: Decodable {
            struct Model: Decodable {
                let name: String
                let supportedGenerationMethods: [String]?
            }

            let models: [Model]?
        }
        let models = (try? JSONDecoder().decode(List.self, from: data))?.models ?? []
        return models
            .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? false }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .sorted()
    }
}

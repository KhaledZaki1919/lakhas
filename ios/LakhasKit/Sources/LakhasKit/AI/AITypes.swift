import Foundation

/// The AI providers a user can bring a key for (ADR-020).
public enum AIProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case anthropic, openai, gemini, openrouter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic Claude"
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .openrouter: "OpenRouter"
        }
    }

    /// Where the user creates an API key.
    public var keyPageURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .openrouter: URL(string: "https://openrouter.ai/keys")
        }
    }

    /// Fast, low-cost default (photo analysis without High accuracy, and all text tasks).
    /// Anthropic IDs are current (2026-10). Gemini uses Google's auto-updating aliases. The
    /// others are starting points: once a key is set, the picker shows the provider's live list.
    public var recommendedStandardModel: String {
        switch self {
        case .anthropic: "claude-haiku-5-5"
        case .openai: "gpt-5-mini"
        case .gemini: "gemini-flash-latest"
        case .openrouter: "google/gemini-flash-latest"
        }
    }

    /// Stronger model used for photo analysis when "High accuracy" is on.
    public var recommendedAccurateModel: String {
        switch self {
        case .anthropic: "claude-sonnet-5-5"
        case .openai: "gpt-5"
        case .gemini: "gemini-pro-latest"
        case .openrouter: "anthropic/claude-sonnet-5.5"
        }
    }

    /// Shown before a key is set (the live list replaces it afterwards).
    public var builtInModels: [String] {
        switch self {
        case .anthropic: ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]
        case .openai: ["gpt-5-mini", "gpt-5"]
        case .gemini: ["gemini-flash-latest", "gemini-pro-latest"]
        case .openrouter: ["google/gemini-flash-latest", "anthropic/claude-haiku-5.5", "anthropic/claude-sonnet-5.5"]
        }
    }

    /// Whether requests start with the provider's native schema enforcement (Gemini gets its
    /// OpenAPI `responseSchema`). A provider that rejects it is retried with the schema in the
    /// prompt (`StructuredAI`); every response is validated either way.
    public var supportsStructuredOutput: Bool { true }

    public func makeProvider(apiKey: String, session: URLSession = .shared) -> AIProvider {
        switch self {
        case .anthropic: AnthropicProvider(apiKey: apiKey, session: session)
        case .openai, .openrouter: OpenAICompatibleProvider(kind: self, apiKey: apiKey, session: session)
        case .gemini: GeminiProvider(apiKey: apiKey, session: session)
        }
    }
}

/// What an AI request is for (usage records, model routing).
public enum AIFeature: String, Codable, Sendable, CaseIterable {
    case photo, text, correction, label, recipe, connectionTest
}

public struct AIRequest: Sendable, Equatable {
    public var system: String
    public var userText: String
    /// JPEG images, already downscaled with metadata stripped.
    public var images: [Data]
    /// JSON Schema of the expected answer (see `JSONSchema`).
    public var schema: JSONValue
    public var schemaName: String
    public var maxOutputTokens: Int

    public init(system: String, userText: String, images: [Data] = [], schema: JSONValue,
                schemaName: String = "result", maxOutputTokens: Int = 2048) {
        self.system = system
        self.userText = userText
        self.images = images
        self.schema = schema
        self.schemaName = schemaName
        self.maxOutputTokens = maxOutputTokens
    }

    /// For providers without native structured output, or after a provider rejected it.
    func withSchemaInstructions() -> AIRequest {
        var copy = self
        copy.system += "\n\nReply with only one JSON object, no prose and no code fences. It must match this JSON Schema:\n"
            + schema.jsonString()
        return copy
    }

    /// The one retry after an invalid answer.
    func withRetryNote(_ problem: String) -> AIRequest {
        var copy = self
        copy.userText += "\n\n<validation_error>Your previous reply was not valid: \(problem). "
            + "Reply again with only the corrected JSON object.</validation_error>"
        return copy
    }
}

public struct AIUsage: Sendable, Equatable, Codable {
    /// Uncached input tokens.
    public let inputTokens: Int
    public let outputTokens: Int
    /// Prompt tokens served from the provider's cache (billed at ~10% of input).
    public let cacheReadTokens: Int
    /// Prompt tokens written to the cache (billed at ~125% of input).
    public let cacheWriteTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    public var totalInputTokens: Int { inputTokens + cacheReadTokens + cacheWriteTokens }
}

public struct AIResponse: Sendable, Equatable {
    public let text: String
    public let usage: AIUsage?
    public let model: String
}

public enum AIError: Error, Equatable, Sendable {
    case noKey
    case invalidKey
    case insufficientCredit
    case rateLimited
    case modelNotFound
    case refused
    case truncated
    case invalidOutput(String)
    case network
    case providerUnavailable
    case badRequest(String)
    case dailyLimitReached
}

/// One provider implementation (plain URLSession, no SDKs).
public protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    /// `structured`: ask the provider to enforce `request.schema` natively.
    func complete(_ request: AIRequest, model: String, structured: Bool) async throws -> AIResponse
    func listModels() async throws -> [String]
}

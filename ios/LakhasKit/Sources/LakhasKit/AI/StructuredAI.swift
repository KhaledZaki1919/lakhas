import Foundation

/// Answers that can check themselves after decoding (ranges, required content).
public protocol AIValidatable {
    func validate() throws
}

public struct AIValidationError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Reported after every provider call that returned (successfully or not), so the app can
/// record usage and cost (ADR-020 §usage).
public struct AIUsageEvent: Sendable, Equatable {
    public let provider: AIProviderKind
    public let model: String
    public let feature: AIFeature
    public let usage: AIUsage?
    public let success: Bool
}

public struct StructuredResult<Value> {
    public let value: Value
    public let usage: AIUsage?
    public let model: String
    public let attempts: Int
}

/// Schema → provider → JSON → `Codable` + `validate()`, with one retry on an invalid answer.
/// If a provider rejects native structured output (some OpenRouter models, older Claude
/// models), the call is repeated once in prompt-only JSON mode before anything else.
public struct StructuredAI: Sendable {
    public let provider: AIProvider
    public let model: String
    private let onUsage: @Sendable (AIUsageEvent) -> Void

    public init(provider: AIProvider, model: String, onUsage: @escaping @Sendable (AIUsageEvent) -> Void = { _ in }) {
        self.provider = provider
        self.model = model
        self.onUsage = onUsage
    }

    public func run<Value: Decodable & AIValidatable>(
        _ type: Value.Type, request: AIRequest, feature: AIFeature
    ) async throws -> StructuredResult<Value> {
        var structured = provider.kind.supportsStructuredOutput
        var fellBack = false
        var current = request
        var lastProblem = "invalid reply"
        var attempt = 0

        while attempt < 2 {
            attempt += 1
            let prepared = structured ? current : current.withSchemaInstructions()
            let response: AIResponse
            do {
                response = try await provider.complete(prepared, model: model, structured: structured)
            } catch AIError.badRequest(let message) where structured && !fellBack && Self.looksLikeSchemaRejection(message) {
                structured = false
                fellBack = true
                attempt -= 1
                continue
            } catch {
                report(feature: feature, usage: nil, success: false)
                throw error
            }

            do {
                let value = try Self.decode(Value.self, from: response.text)
                try value.validate()
                report(feature: feature, usage: response.usage, success: true)
                return StructuredResult(value: value, usage: response.usage, model: response.model, attempts: attempt)
            } catch {
                report(feature: feature, usage: response.usage, success: false)
                lastProblem = Self.describe(error)
                current = request.withRetryNote(lastProblem)
            }
        }
        throw AIError.invalidOutput(lastProblem)
    }

    private func report(feature: AIFeature, usage: AIUsage?, success: Bool) {
        onUsage(AIUsageEvent(provider: provider.kind, model: model, feature: feature, usage: usage, success: success))
    }

    static func looksLikeSchemaRejection(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["response_format", "json_schema", "output_config", "structured output", "schema"].contains { lower.contains($0) }
    }

    /// Accepts bare JSON, JSON in code fences, or JSON surrounded by stray text.
    static func extractJSON(_ text: String) -> Data? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else { return nil }
        return Data(trimmed[start...end].utf8)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from text: String) throws -> Value {
        guard let data = extractJSON(text) else { throw AIValidationError("no JSON object found") }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case let error as AIValidationError:
            return error.description
        case DecodingError.keyNotFound(let key, _):
            return "missing field \"\(key.stringValue)\""
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            return "wrong type at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case DecodingError.dataCorrupted:
            return "malformed JSON"
        default:
            return "invalid reply"
        }
    }
}

/// Minimal request used by Settings → AI "Test connection".
public enum ConnectionTest {
    public struct Reply: Decodable, AIValidatable {
        public let ok: Bool

        public func validate() throws {
            guard ok else { throw AIValidationError("ok must be true") }
        }
    }

    public static let request = AIRequest(
        system: "You are a connection test for a nutrition app.",
        userText: "Reply with {\"ok\": true}.",
        schema: JSONSchema.object(["ok": JSONSchema.boolean]),
        schemaName: "connection_test",
        maxOutputTokens: 1024
    )
}

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
    /// Strings to remove from diagnostics (the API key).
    private let secrets: [String]
    private let onDiagnostic: @Sendable (AIDiagnostic) -> Void
    private let onUsage: @Sendable (AIUsageEvent) -> Void

    public init(provider: AIProvider, model: String, secrets: [String] = [],
                onDiagnostic: @escaping @Sendable (AIDiagnostic) -> Void = { _ in },
                onUsage: @escaping @Sendable (AIUsageEvent) -> Void = { _ in }) {
        self.provider = provider
        self.model = model
        self.secrets = secrets
        self.onDiagnostic = onDiagnostic
        self.onUsage = onUsage
    }

    /// Where a run ended, for the diagnostic.
    private struct Failure {
        var step: AIDiagnostic.Step
        var message: String?
        var reply: String?
    }

    private final class RunState: @unchecked Sendable {
        var calls = 0
        var failure: Failure?
    }

    public func run<Value: Decodable & AIValidatable>(
        _ type: Value.Type, request: AIRequest, feature: AIFeature, trace: AITrace = AITrace()
    ) async throws -> StructuredResult<Value> {
        let state = RunState()
        let started = Date()
        do {
            let result = try await AITrace.$current.withValue(trace) {
                try await attempts(type, request: request, feature: feature, trace: trace, state: state)
            }
            emitDiagnostic(feature: feature, trace: trace, state: state, started: started)
            return result
        } catch {
            if state.failure == nil {
                state.failure = Failure(step: trace.status == nil ? .network : .http, message: nil, reply: nil)
            }
            emitDiagnostic(feature: feature, trace: trace, state: state, started: started)
            throw error
        }
    }

    private func attempts<Value: Decodable & AIValidatable>(
        _ type: Value.Type, request: AIRequest, feature: AIFeature, trace: AITrace, state: RunState
    ) async throws -> StructuredResult<Value> {
        var structured = provider.kind.supportsStructuredOutput
        var fellBack = false
        var current = request
        var lastProblem = "invalid reply"
        var attempt = 0

        while attempt < 2 {
            attempt += 1
            state.calls += 1
            state.failure = nil
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
                state.failure = Self.failure(for: error, trace: trace)
                report(feature: feature, usage: nil, success: false)
                throw error
            }

            let value: Value
            do {
                value = try Self.decode(Value.self, from: response.text)
            } catch {
                lastProblem = Self.describe(error)
                state.failure = Failure(step: .json, message: lastProblem, reply: response.text)
                report(feature: feature, usage: response.usage, success: false)
                current = request.withRetryNote(lastProblem)
                continue
            }
            do {
                try value.validate()
            } catch {
                lastProblem = Self.describe(error)
                state.failure = Failure(step: .validation, message: lastProblem, reply: response.text)
                report(feature: feature, usage: response.usage, success: false)
                current = request.withRetryNote(lastProblem)
                continue
            }
            report(feature: feature, usage: response.usage, success: true)
            return StructuredResult(value: value, usage: response.usage, model: response.model, attempts: attempt)
        }
        throw AIError.invalidOutput(lastProblem)
    }

    /// Provider errors: no response (network), an error status (http), or a 2xx whose envelope
    /// was unusable (response).
    private static func failure(for error: Error, trace: AITrace) -> Failure {
        guard let status = trace.status else {
            return Failure(step: .network, message: trace.networkError, reply: nil)
        }
        if !(200..<300).contains(status) {
            return Failure(step: .http, message: trace.body.flatMap(AIHTTP.errorMessage), reply: nil)
        }
        return Failure(step: .response, message: String(describing: error), reply: nil)
    }

    private func emitDiagnostic(feature: AIFeature, trace: AITrace, state: RunState, started: Date) {
        let failure = state.failure
        let status = trace.status
        let showsBody = failure?.step == .http || failure?.step == .response
        onDiagnostic(AIDiagnostic(
            date: started,
            provider: provider.kind,
            model: model,
            feature: feature,
            endpoint: trace.endpoint.map { AIRedactor.redact($0, secrets: secrets) },
            httpStatus: status,
            failedStep: failure?.step,
            attempts: state.calls,
            durationMs: Int(Date().timeIntervalSince(started) * 1000),
            message: failure?.message.map { AIRedactor.redact($0, secrets: secrets) },
            errorBody: showsBody ? AIRedactor.excerpt(trace.body, secrets: secrets) : nil,
            replyExcerpt: failure?.reply.flatMap { AIRedactor.excerpt($0, secrets: secrets, limit: 1500) }
        ))
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

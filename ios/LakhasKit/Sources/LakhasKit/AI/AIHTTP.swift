import Foundation

/// Shared HTTP plumbing and error mapping for the providers.
enum AIHTTP {
    /// Provider responses use snake_case keys; models use camelCase properties.
    static var snakeCaseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func jsonRequest(url: URL, headers: [String: String], body: JSONValue, timeout: TimeInterval = 180) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func getRequest(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    /// With `retryTransient`, an overloaded server (5xx) or a rate limit that asks for a short
    /// wait (Gemini's free tier) is retried once after the delay. The endpoint, status and body
    /// (or the network error) go to `AITrace.current` for the diagnostics screen. The timeout
    /// is long because non-streamed replies from thinking models with photos can take a while.
    static func send(_ request: URLRequest, session: URLSession, retryTransient: Bool = false) async throws -> Data {
        var attempt = 0
        let trace = AITrace.current
        while true {
            trace?.begin(request.url)
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                trace?.failed(error)
                throw AIError.network
            }
            guard let http = response as? HTTPURLResponse else { throw AIError.network }
            trace?.received(status: http.statusCode, body: data)
            if (200..<300).contains(http.statusCode) { return data }
            let error = mapError(status: http.statusCode, body: data)
            guard retryTransient, attempt == 0, let delay = retryDelay(status: http.statusCode, body: data) else { throw error }
            attempt += 1
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    /// Seconds to wait before one retry, or nil when retrying soon wouldn't help.
    static func retryDelay(status: Int, body: Data, maxWait: TimeInterval = 20) -> TimeInterval? {
        switch status {
        case 500...599:
            return 2
        case 429:
            // Gemini: {"error":{"details":[{"@type":"…RetryInfo","retryDelay":"17s"}]}}
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: body),
                  case .array(let details)? = json["error"]?["details"] else { return nil }
            for detail in details {
                if case .string(let text)? = detail["retryDelay"],
                   let seconds = TimeInterval(text.trimmingCharacters(in: CharacterSet(charactersIn: "s"))) {
                    return seconds <= maxWait ? seconds + 0.5 : nil
                }
            }
            return nil
        default:
            return nil
        }
    }

    static func mapError(status: Int, body: Data) -> AIError {
        let message = errorMessage(body) ?? ""
        let lower = message.lowercased()
        let mentionsBilling = ["credit", "billing", "quota", "insufficient", "balance", "payment"].contains { lower.contains($0) }
        // Gemini says "exceeded your current quota" for free-tier per-minute and daily limits too;
        // that's a rate limit, not missing credit.
        if case .string("RESOURCE_EXHAUSTED")? = (try? JSONDecoder().decode(JSONValue.self, from: body))?["error"]?["status"] {
            return .rateLimited
        }
        switch status {
        case 401, 403:
            return .invalidKey
        case 402:
            return .insufficientCredit
        case 404:
            return .modelNotFound
        case 429:
            return mentionsBilling ? .insufficientCredit : .rateLimited
        case 400:
            if lower.contains("api key") && (lower.contains("invalid") || lower.contains("not valid")) { return .invalidKey }
            if mentionsBilling { return .insufficientCredit }
            let missingModel = ["not found", "does not exist", "invalid model", "not a valid model"]
            if lower.contains("model") && missingModel.contains(where: { lower.contains($0) }) {
                return .modelNotFound
            }
            return .badRequest(message)
        case 500...599:
            return .providerUnavailable
        default:
            return .badRequest(message.isEmpty ? "HTTP \(status)" : message)
        }
    }

    /// Error text from `{"error": {"message": …}}`, `{"error": "…"}` or `{"message": "…"}`.
    static func errorMessage(_ data: Data) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        if case .string(let text)? = json["error"]?["message"] { return text }
        if case .string(let text)? = json["error"] { return text }
        if case .string(let text)? = json["message"] { return text }
        return nil
    }
}

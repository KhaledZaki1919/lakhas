import Foundation

/// Shared HTTP plumbing and error mapping for the providers.
enum AIHTTP {
    /// Provider responses use snake_case keys; models use camelCase properties.
    static var snakeCaseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func jsonRequest(url: URL, headers: [String: String], body: JSONValue, timeout: TimeInterval = 90) throws -> URLRequest {
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

    static func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError.network
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, body: data)
        }
        return data
    }

    static func mapError(status: Int, body: Data) -> AIError {
        let message = errorMessage(body) ?? ""
        let lower = message.lowercased()
        let mentionsBilling = ["credit", "billing", "quota", "insufficient", "balance", "payment"].contains { lower.contains($0) }
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

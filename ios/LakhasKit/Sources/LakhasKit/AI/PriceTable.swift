import Foundation

/// USD per million tokens.
public struct ModelPrice: Codable, Sendable, Equatable {
    public var inputPerMillion: Double
    public var outputPerMillion: Double

    public init(inputPerMillion: Double, outputPerMillion: Double) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
    }
}

/// Cost estimates (ADR-020 open question 4): a bundled table plus the user's own overrides.
/// Always shown as "estimated". Unknown models show token counts without a cost.
public enum PriceTable {
    /// Anthropic list prices as of 2026-10 (Haiku 5.5: prompts up to 100K tokens).
    public static let builtIn: [String: ModelPrice] = [
        "claude-haiku-5-5": ModelPrice(inputPerMillion: 0.10, outputPerMillion: 0.50),
        "claude-sonnet-5-5": ModelPrice(inputPerMillion: 2, outputPerMillion: 10),
        "claude-opus-5-5": ModelPrice(inputPerMillion: 4, outputPerMillion: 20),
        "claude-sonnet-5": ModelPrice(inputPerMillion: 2, outputPerMillion: 10),
        "claude-haiku-4-5": ModelPrice(inputPerMillion: 1, outputPerMillion: 5),
        "claude-sonnet-4-6": ModelPrice(inputPerMillion: 3, outputPerMillion: 15),
    ]

    public static let overridesKey = "aiPriceOverrides"

    public static func overrides(from defaults: UserDefaults = .standard) -> [String: ModelPrice] {
        guard let data = defaults.data(forKey: overridesKey),
              let value = try? JSONDecoder().decode([String: ModelPrice].self, from: data) else { return [:] }
        return value
    }

    public static func setOverride(_ price: ModelPrice?, for model: String, in defaults: UserDefaults = .standard) {
        var current = overrides(from: defaults)
        current[model] = price
        if let data = try? JSONEncoder().encode(current) { defaults.set(data, forKey: overridesKey) }
    }

    /// Exact match first (overrides win), then the OpenRouter form "anthropic/claude-haiku-5.5".
    public static func price(for model: String, overrides: [String: ModelPrice] = [:]) -> ModelPrice? {
        if let price = overrides[model] ?? builtIn[model] { return price }
        let normalized = (model.split(separator: "/").last.map(String.init) ?? model)
            .replacingOccurrences(of: ".", with: "-")
        return overrides[normalized] ?? builtIn[normalized]
    }

    public static func cost(of usage: AIUsage, at price: ModelPrice) -> Double {
        let input = Double(usage.inputTokens) + Double(usage.cacheReadTokens) * 0.1 + Double(usage.cacheWriteTokens) * 1.25
        return (input * price.inputPerMillion + Double(usage.outputTokens) * price.outputPerMillion) / 1_000_000
    }

    public static func estimatedCost(of usage: AIUsage?, model: String, overrides: [String: ModelPrice] = [:]) -> Double? {
        guard let usage, let price = price(for: model, overrides: overrides) else { return nil }
        return cost(of: usage, at: price)
    }
}

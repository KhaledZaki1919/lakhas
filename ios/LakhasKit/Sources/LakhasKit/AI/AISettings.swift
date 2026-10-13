import Foundation

/// The user's API keys: one Keychain item per provider, readable only while the device is
/// unlocked, never synced or backed up (ADR-020). Keys are never logged or exported.
public struct AIKeyStore: Sendable {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore(service: "lakhas.ai-keys", accessibility: .whenUnlockedThisDeviceOnly)) {
        self.keychain = keychain
    }

    public func key(for provider: AIProviderKind) -> String? {
        guard let data = try? keychain.read(account: provider.rawValue),
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    public func hasKey(for provider: AIProviderKind) -> Bool { key(for: provider) != nil }

    public func save(_ key: String, for provider: AIProviderKind) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete(for: provider) }
        try keychain.save(Data(trimmed.utf8), account: provider.rawValue)
    }

    public func delete(for provider: AIProviderKind) {
        try? keychain.delete(account: provider.rawValue)
    }

    public func deleteAll() {
        AIProviderKind.allCases.forEach(delete(for:))
    }

    /// "sk-ant-a…9f3c" for display.
    public static func masked(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(8))…\(key.suffix(4))"
    }
}

/// Provider, models, High accuracy and the optional daily limit (UserDefaults; no secrets).
public struct AISettings: Codable, Sendable, Equatable {
    public var provider: AIProviderKind
    public var standardModels: [String: String]
    public var accurateModels: [String: String]
    public var highAccuracy: Bool
    /// AI requests per local day; nil = no limit (default).
    public var dailyLimit: Int?

    public static let defaultsKey = "aiSettings"

    public init(provider: AIProviderKind = .anthropic, standardModels: [String: String] = [:],
                accurateModels: [String: String] = [:], highAccuracy: Bool = false, dailyLimit: Int? = nil) {
        self.provider = provider
        self.standardModels = standardModels
        self.accurateModels = accurateModels
        self.highAccuracy = highAccuracy
        self.dailyLimit = dailyLimit
    }

    public static func load(from defaults: UserDefaults = .standard) -> AISettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AISettings.self, from: data) else { return AISettings() }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    public func standardModel(for provider: AIProviderKind) -> String {
        standardModels[provider.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? provider.recommendedStandardModel
    }

    public func accurateModel(for provider: AIProviderKind) -> String {
        accurateModels[provider.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? provider.recommendedAccurateModel
    }

    /// Photo analysis uses the stronger model when High accuracy is on; everything else
    /// (text entry, corrections, labels, recipes) stays on the cheaper default.
    public func model(for feature: AIFeature) -> String {
        feature == .photo && highAccuracy ? accurateModel(for: provider) : standardModel(for: provider)
    }
}

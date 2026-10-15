import Foundation

/// The user's API keys: one Keychain item per provider, readable only while the device is
/// unlocked, never synced or backed up (ADR-020). Keys are never logged or exported.
public struct AIKeyStore: Sendable {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore(service: "lakhas.ai-keys", accessibility: .whenUnlockedThisDeviceOnly)) {
        self.keychain = keychain
    }

    /// Sanitized on read too, so a key saved before sanitizing existed still works.
    public func key(for provider: AIProviderKind) -> String? {
        guard let data = try? keychain.read(account: provider.rawValue),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let key = Self.sanitize(raw)
        return key.isEmpty ? nil : key
    }

    public func hasKey(for provider: AIProviderKind) -> Bool { key(for: provider) != nil }

    public func save(_ key: String, for provider: AIProviderKind) throws {
        let clean = Self.sanitize(key)
        guard !clean.isEmpty else { return delete(for: provider) }
        try keychain.save(Data(clean.utf8), account: provider.rawValue)
    }

    /// Pasted keys often carry spaces, line breaks, wrapping quotes, a "Bearer " prefix, or
    /// invisible characters (zero-width spaces, LTR/RTL marks from Arabic text). Any of these
    /// breaks the auth header, so they're removed. Nothing else about the key changes.
    public static func sanitize(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            let category = scalar.properties.generalCategory
            return !(scalar.properties.isWhitespace || category == .format || category == .control)
        }
        var key = String(String.UnicodeScalarView(scalars))
        if key.lowercased().hasPrefix("bearer") && raw.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("bearer ") {
            key.removeFirst("bearer".count)
        }
        let wrappers = CharacterSet(charactersIn: "\"'`“”‘’<>")
        return key.trimmingCharacters(in: wrappers)
    }

    /// Format hints shown while typing. They never block saving: providers change formats
    /// (Google's AI Studio has issued "AQ." keys since 2026-05-28, alongside older "AIza" keys).
    public static func warnings(for key: String, provider: AIProviderKind) -> [AIKeyWarning] {
        let clean = sanitize(key)
        guard !clean.isEmpty else { return [] }
        var warnings: [AIKeyWarning] = []
        if let owner = AIProviderKind.owner(ofKey: clean) {
            if owner != provider { warnings.append(.looksLike(owner)) }
        } else {
            warnings.append(.unexpectedFormat)
        }
        if !clean.unicodeScalars.allSatisfy({ $0.isASCII }) { warnings.append(.unexpectedCharacters) }
        if clean.count < 20 { warnings.append(.tooShort) }
        return warnings
    }

    public func delete(for provider: AIProviderKind) {
        try? keychain.delete(account: provider.rawValue)
    }

    public func deleteAll() {
        AIProviderKind.allCases.forEach(delete(for:))
    }

    /// "AQ.A…9f3c · 39" for display: first 4, last 4 and the length.
    public static func masked(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(4))…\(key.suffix(4)) · \(key.count)"
    }
}

public enum AIKeyWarning: Equatable, Sendable {
    /// The key has another provider's format (e.g. "sk-ant-" in the Gemini field).
    case looksLike(AIProviderKind)
    /// Not a format we know for any provider.
    case unexpectedFormat
    /// Non-ASCII characters remain after cleaning.
    case unexpectedCharacters
    case tooShort
}

extension AIProviderKind {
    /// Usual key prefixes, for the format hint.
    public var keyPrefixes: [String] {
        switch self {
        case .anthropic: ["sk-ant-"]
        case .openai: ["sk-"]
        case .gemini: ["AIza", "AQ."]
        case .openrouter: ["sk-or-"]
        }
    }

    /// The provider whose key format this is, most specific prefix first.
    public static func owner(ofKey key: String) -> AIProviderKind? {
        if key.hasPrefix("sk-ant-") { return .anthropic }
        if key.hasPrefix("sk-or-") { return .openrouter }
        if key.hasPrefix("AIza") || key.hasPrefix("AQ.") { return .gemini }
        if key.hasPrefix("sk-") { return .openai }
        return nil
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

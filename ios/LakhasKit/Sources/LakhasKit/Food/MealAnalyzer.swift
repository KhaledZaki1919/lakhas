import CryptoKit
import Foundation

/// Builds prompts from the versioned resources (PROJECT_PROMPT.md §7).
public enum PromptLibrary {
    public static let version = "v1"

    static func load(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: "\(name).\(version)", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    static func candidateLines(_ foods: [FoodEntry]) -> String {
        foods.map { "\($0.id) | \($0.nameAr) | \($0.nameEn) | \(Int($0.per100.kcal.rounded()))" }.joined(separator: "\n")
    }

    static func system(task: String, language: String, candidates: [FoodEntry], leftover: Bool = false) -> String {
        let common = load("common")
            .replacingOccurrences(of: "{{LANGUAGE_NAME}}", with: language == "ar" ? "Arabic" : "English")
            .replacingOccurrences(of: "{{CANDIDATES}}", with: candidateLines(candidates))
        let leftoverRule = leftover
            ? "Two images are attached: the first shows the meal before eating, the second shows what was left. "
                + "grams always refers to the first image. For each item set leftoverGrams to the grams still left "
                + "in the second image (0 if it was finished)."
            : "Set leftoverGrams to null."
        let taskText = load(task).replacingOccurrences(of: "{{LEFTOVER_RULE}}", with: leftoverRule)
        return common + "\n\n" + taskText
    }

    /// User text is always wrapped as data (injection resistance).
    static func wrap(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "</user_content>", with: "")
        return "<user_content>\n\(cleaned)\n</user_content>"
    }
}

/// Same input on the same day reuses the earlier result at no cost (PROJECT_PROMPT.md §5).
public struct AIResultCache: Sendable {
    let directory: URL

    public init(location: StoreLocation = AppGroupResolver.resolve()) {
        directory = location.directory.appendingPathComponent("AICache", isDirectory: true)
    }

    init(directory: URL) {
        self.directory = directory
    }

    public static func key(parts: [Data]) -> String {
        var hasher = SHA256()
        for part in parts {
            hasher.update(data: part)
            hasher.update(data: Data([0x1F]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private struct Entry: Codable {
        let analysis: MealAnalysis
        let model: String
    }

    public func load(_ key: String, day: String) -> (analysis: MealAnalysis, model: String)? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(day).appendingPathComponent("\(key).json")),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        return (entry.analysis, entry.model)
    }

    public func store(_ analysis: MealAnalysis, model: String, key: String, day: String) {
        guard let data = try? JSONEncoder().encode(Entry(analysis: analysis, model: model)) else { return }
        try? FileProtection.write(data, to: directory.appendingPathComponent(day).appendingPathComponent("\(key).json"))
    }

    /// Keeps only today's folder.
    public func purge(keeping day: String) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.lastPathComponent != day {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

/// Photo, text and correction analysis (ADR-020): prompt → `AIService` → validation →
/// DB override for confident matches → leftovers subtracted → editable draft items.
@MainActor
public final class MealAnalyzer {
    public struct Outcome: Sendable {
        public let items: [DraftItem]
        public let notes: String?
        public let model: String
        public let estimatedCost: Double?
        public let fromCache: Bool
    }

    /// Model matches at or above this confidence take the DB's per-100 g values (§7.2).
    public static let dbOverrideConfidence = 0.6

    private let service: AIService
    private let database: FoodDatabase
    private let cache: AIResultCache

    public init(service: AIService, database: FoodDatabase = .shared, cache: AIResultCache = AIResultCache()) {
        self.service = service
        self.database = database
        self.cache = cache
    }

    /// Curated dishes always go in the photo prompt (the model can't search before it sees).
    private var photoCandidates: [FoodEntry] {
        database.foods.filter(\.isCurated) + database.foods.filter { !$0.isCurated && ["bread", "eggs", "dairy", "fruits"].contains($0.category) }
    }

    public func analyzePhoto(_ meal: Data, leftover: Data?, note: String = "", language: String) async throws -> Outcome {
        var images = [meal]
        if let leftover { images.append(leftover) }
        let request = AIRequest(
            system: PromptLibrary.system(task: "photo", language: language, candidates: photoCandidates, leftover: leftover != nil),
            userText: note.isEmpty ? "Analyze this meal." : PromptLibrary.wrap(note),
            images: images,
            schema: MealAnalysis.schema,
            schemaName: "meal_analysis",
            maxOutputTokens: 4096
        )
        return try await run(request, feature: .photo, language: language, cacheParts: images + [Data(note.utf8)])
    }

    public func analyzeText(_ text: String, language: String) async throws -> Outcome {
        let request = AIRequest(
            system: PromptLibrary.system(task: "text", language: language, candidates: database.candidates(for: text)),
            userText: PromptLibrary.wrap(text),
            schema: MealAnalysis.schema,
            schemaName: "meal_analysis",
            maxOutputTokens: 4096
        )
        return try await run(request, feature: .text, language: language, cacheParts: [Data(text.utf8)])
    }

    public func correct(_ items: [DraftItem], correction: String, language: String) async throws -> Outcome {
        let current = MealAnalysis(items: items.map(\.analysisItem), notes: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let currentJSON = String(bytes: (try? encoder.encode(current)) ?? Data(), encoding: .utf8) ?? "{}"
        let candidates = database.candidates(for: correction + " " + items.map(\.nameEn).joined(separator: " "))
        let request = AIRequest(
            system: PromptLibrary.system(task: "correct", language: language, candidates: candidates),
            userText: "<current_items>\n\(currentJSON)\n</current_items>\n\n" + PromptLibrary.wrap(correction),
            schema: MealAnalysis.schema,
            schemaName: "meal_analysis",
            maxOutputTokens: 4096
        )
        return try await run(request, feature: .correction, language: language, cacheParts: [Data(currentJSON.utf8), Data(correction.utf8)])
    }

    private func run(_ request: AIRequest, feature: AIFeature, language: String, cacheParts: [Data]) async throws -> Outcome {
        let model = service.settings.model(for: feature)
        let day = DayKey.make(.now)
        let key = AIResultCache.key(parts: [Data(feature.rawValue.utf8), Data(language.utf8), Data(model.utf8),
                                            Data(PromptLibrary.version.utf8)] + cacheParts)
        cache.purge(keeping: day)
        if let hit = cache.load(key, day: day) {
            return Outcome(items: Self.postProcess(hit.analysis, database: database), notes: hit.analysis.notes,
                           model: hit.model, estimatedCost: 0, fromCache: true)
        }
        let result = try await service.run(MealAnalysis.self, request: request, feature: feature)
        cache.store(result.value, model: result.model, key: key, day: day)
        let cost = PriceTable.estimatedCost(of: result.usage, model: result.model, overrides: PriceTable.overrides())
        return Outcome(items: Self.postProcess(result.value, database: database), notes: result.value.notes,
                       model: result.model, estimatedCost: cost, fromCache: false)
    }

    /// DB values replace the model's per-100 g when the match is confident; otherwise the
    /// model's values stand. Leftovers are subtracted from the served grams.
    public static func postProcess(_ analysis: MealAnalysis, database: FoodDatabase) -> [DraftItem] {
        analysis.items.map { item in
            let match = item.foodDbId.flatMap(database.food(id:))
            let useDB = match != nil && item.confidence >= dbOverrideConfidence
            let per100 = useDB
                ? (match?.macros ?? Macros.zero)
                : Macros(kcal: item.per100.kcal, protein: item.per100.protein, carbs: item.per100.carbs, fat: item.per100.fat)
            let leftover = item.leftoverGrams.map { min(max($0, 0), item.grams) }
            return DraftItem(
                nameAr: item.nameAr, nameEn: item.nameEn,
                grams: (item.grams - (leftover ?? 0)).rounded(),
                per100: per100,
                valueSource: useDB ? .db : .ai,
                foodDbId: match?.id,
                confidence: item.confidence,
                servedGrams: leftover == nil ? nil : item.grams,
                leftoverGrams: leftover
            )
        }
    }
}

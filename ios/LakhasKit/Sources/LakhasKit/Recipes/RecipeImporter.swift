import Foundation

/// Recipe import (PROJECT_PROMPT.md §4.4): public page text, pasted text or screenshots →
/// the user's provider with the standard model (`recipe.v1`) → validated → editable draft.
/// The same input on the same day reuses the earlier answer at no cost.
@MainActor
public final class RecipeImporter {
    public enum Input: Sendable {
        case page(RecipePageText)
        case text(String)
        /// JPEGs already downscaled with metadata stripped, in reading order.
        case screenshots([Data])
    }

    public struct Outcome: Sendable {
        /// nil when the model found no recipe (`notes` says why).
        public let draft: RecipeDraft?
        public let notes: String?
        public let model: String
        public let estimatedCost: Double?
        public let fromCache: Bool
    }

    public nonisolated static let maxScreenshots = 6
    /// Pasted text sent to the model, at most.
    public nonisolated static let maxTextCharacters = 8000

    private let service: AIService
    private let database: FoodDatabase
    private let cache: AIResultCache

    public init(service: AIService, database: FoodDatabase = .shared, cache: AIResultCache = AIResultCache()) {
        self.service = service
        self.database = database
        self.cache = cache
    }

    public func extract(_ input: Input, language: String) async throws -> Outcome {
        let request = Self.request(for: input, language: language, database: database)
        let model = service.settings.model(for: .recipe)
        let day = DayKey.make(.now)
        let key = AIResultCache.key(parts: [Data(AIFeature.recipe.rawValue.utf8), Data(language.utf8), Data(model.utf8),
                                            Data(PromptLibrary.version.utf8), Data(request.userText.utf8)] + request.images)
        cache.purge(keeping: day)
        if let hit = cache.value(RecipeExtraction.self, key: key, day: day) {
            return outcome(hit.value, input: input, language: language, model: hit.model, cost: 0, fromCache: true)
        }
        let result = try await service.run(RecipeExtraction.self, request: request, feature: .recipe)
        cache.store(result.value, model: result.model, key: key, day: day)
        let cost = PriceTable.estimatedCost(of: result.usage, model: result.model, overrides: PriceTable.overrides())
        return outcome(result.value, input: input, language: language, model: result.model, cost: cost, fromCache: false)
    }

    nonisolated static func request(for input: Input, language: String, database: FoodDatabase) -> AIRequest {
        let userText: String
        var images: [Data] = []
        var candidateText = ""
        switch input {
        case .page(let page):
            userText = "Extract the recipe from this public \(page.platform.displayName) post.\n"
                + PromptLibrary.wrap(page.text, tag: "page_content")
            candidateText = page.text
        case .text(let text):
            let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextCharacters))
            userText = "Extract the recipe from this text.\n" + PromptLibrary.wrap(trimmed)
            candidateText = trimmed
        case .screenshots(let shots):
            images = Array(shots.prefix(maxScreenshots))
            userText = images.count == 1
                ? "Extract the recipe from this screenshot."
                : "Extract the recipe from these \(images.count) screenshots, in order."
        }
        let system = PromptLibrary.load("recipe")
            .replacingOccurrences(of: "{{LANGUAGE_NAME}}", with: language == "ar" ? "Arabic" : "English")
            .replacingOccurrences(of: "{{CANDIDATES}}", with: PromptLibrary.candidateLines(database.candidates(for: candidateText)))
        return AIRequest(system: system, userText: userText, images: images, schema: RecipeExtraction.schema,
                         schemaName: "recipe", maxOutputTokens: 8192)
    }

    private func outcome(_ extraction: RecipeExtraction, input: Input, language: String, model: String,
                         cost: Double?, fromCache: Bool) -> Outcome {
        guard extraction.found else {
            return Outcome(draft: nil, notes: extraction.notes, model: model, estimatedCost: cost, fromCache: fromCache)
        }
        var draft = RecipeDraft(
            titleAr: extraction.titleAr.trimmingCharacters(in: .whitespaces),
            titleEn: extraction.titleEn.trimmingCharacters(in: .whitespaces),
            servings: Int(extraction.servings.rounded()),
            ingredients: extraction.draftItems(database: database),
            steps: extraction.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            notes: extraction.notes,
            estimated: extraction.estimated,
            source: .text,
            language: language
        )
        switch input {
        case .page(let page):
            draft.source = .link
            draft.sourceURL = page.url
            draft.platform = page.platform
            draft.creatorHandle = page.creatorHandle ?? page.author
        case .text(let text):
            // A pasted caption often still contains its link.
            if let link = RecipeLink.parse(text) {
                draft.sourceURL = RecipeLink.canonical(link)
                draft.platform = RecipeLink.platform(of: link)
            }
        case .screenshots:
            draft.source = .screenshot
        }
        return Outcome(draft: draft, notes: extraction.notes, model: model, estimatedCost: cost, fromCache: fromCache)
    }

    // MARK: Cost estimate before importing

    /// System prompt, food list and wrapper, in tokens.
    nonisolated static let promptTokens = 1600
    /// A ~1568 px screenshot (providers differ; this is on the high side).
    nonisolated static let tokensPerImage = 1600
    /// A typical recipe answer.
    nonisolated static let answerTokens = 1500

    /// A rough USD estimate for one import with `model`, or nil when the model has no price.
    public nonisolated static func estimatedCost(textCharacters: Int, images: Int, model: String,
                                                 overrides: [String: ModelPrice] = PriceTable.overrides()) -> Double? {
        let input = promptTokens + min(textCharacters, maxTextCharacters) / 3 + images * tokensPerImage
        return PriceTable.estimatedCost(of: AIUsage(inputTokens: input, outputTokens: answerTokens), model: model, overrides: overrides)
    }

    /// Characters a link import usually sends (title + caption).
    public nonisolated static let typicalCaptionCharacters = 1200
}

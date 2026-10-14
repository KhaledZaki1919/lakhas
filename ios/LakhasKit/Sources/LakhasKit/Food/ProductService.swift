import Foundation
import SwiftData

/// What the AI reads from two label photos (nutrition table + front). Validated after decoding.
public struct ProductLabel: Codable, Equatable, Sendable, AIValidatable {
    public struct Per100: Codable, Equatable, Sendable {
        public let kcal: Double
        public let protein: Double
        public let carbs: Double
        public let fat: Double
    }

    public let nameAr: String
    public let nameEn: String
    public let brand: String?
    public let servingGrams: Double?
    public let per100: Per100
    public let readable: Bool
    public let notes: String?

    public static let schema: JSONValue = JSONSchema.object([
        "nameAr": JSONSchema.string,
        "nameEn": JSONSchema.string,
        "brand": JSONSchema.nullable("string"),
        "servingGrams": JSONSchema.nullable("number"),
        "per100": JSONSchema.object([
            "kcal": JSONSchema.number,
            "protein": JSONSchema.number,
            "carbs": JSONSchema.number,
            "fat": JSONSchema.number,
        ]),
        "readable": JSONSchema.boolean,
        "notes": JSONSchema.nullable("string"),
    ])

    var macros: Macros { Macros(kcal: per100.kcal, protein: per100.protein, carbs: per100.carbs, fat: per100.fat) }

    public func validate() throws {
        guard readable else { return }
        guard !nameAr.trimmingCharacters(in: .whitespaces).isEmpty || !nameEn.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIValidationError("a readable label needs a product name")
        }
        guard (0...900).contains(per100.kcal) else { throw AIValidationError("kcal per 100 g must be 0–900") }
        for value in [per100.protein, per100.carbs, per100.fat] where !(0...100).contains(value) {
            throw AIValidationError("macros per 100 g must be 0–100")
        }
        guard per100.protein + per100.carbs + per100.fat <= 101 else {
            throw AIValidationError("protein + carbs + fat can't exceed 100 g per 100 g")
        }
        if let servingGrams, !(1...2000).contains(servingGrams) {
            throw AIValidationError("servingGrams must be 1–2000 or null")
        }
    }

    func info(barcode: String) -> ProductInfo {
        let ar = nameAr.trimmingCharacters(in: .whitespaces)
        let en = nameEn.trimmingCharacters(in: .whitespaces)
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespaces)
        return ProductInfo(barcode: barcode, nameAr: ar.isEmpty ? en : ar, nameEn: en.isEmpty ? ar : en,
                           brand: trimmedBrand?.isEmpty == false ? trimmedBrand : nil,
                           servingGrams: servingGrams, per100: macros, source: .label)
    }
}

public enum ProductLookupResult: Equatable, Sendable {
    /// In the local product library (added or logged before).
    case saved(ProductInfo)
    /// Found on Open Food Facts with usable values.
    case openFoodFacts(ProductInfo)
    /// Known to Open Food Facts but without usable nutrition values (the name helps the form).
    case incomplete(ProductInfo)
    case notFound
}

/// Barcode flow (PROJECT_PROMPT.md §4.3 C): local products first, then Open Food Facts. Missing
/// products are read from label photos by the user's AI provider and saved on this device only.
@MainActor
public final class ProductService {
    public struct LabelOutcome: Sendable {
        /// nil when the label couldn't be read.
        public let info: ProductInfo?
        public let notes: String?
        public let model: String
        public let estimatedCost: Double?
        public let fromCache: Bool
    }

    private let context: ModelContext
    private let client: OpenFoodFactsClient

    public init(context: ModelContext, client: OpenFoodFactsClient = OpenFoodFactsClient()) {
        self.context = context
        self.client = client
    }

    public func savedProduct(barcode: String) -> Product? {
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.barcode == barcode })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    public func lookup(_ rawBarcode: String) async throws -> ProductLookupResult {
        guard let barcode = Barcode.normalize(rawBarcode) else { throw ProductLookupError.invalidBarcode }
        if let saved = savedProduct(barcode: barcode) { return .saved(saved.info) }
        guard let found = try await client.product(barcode: barcode) else { return .notFound }
        return found.per100 == nil ? .incomplete(found) : .openFoodFacts(found)
    }

    /// Adds or updates the local product and marks it as used now.
    @discardableResult
    public func save(_ info: ProductInfo, photo: Data? = nil, now: Date = .now) -> Product {
        let product: Product
        if let existing = savedProduct(barcode: info.barcode) {
            existing.update(from: info)
            product = existing
        } else {
            product = Product(info: info, now: now)
            context.insert(product)
        }
        product.lastUsedAt = now
        if let photo, let name = try? MealPhotoStore().save(photo) {
            if let old = product.photoFileName { MealPhotoStore().delete(old) }
            product.photoFileName = name
        }
        try? context.save()
        return product
    }

    /// Reads the nutrition table and front photos (already downscaled, metadata stripped)
    /// with the standard model. The same photos on the same day reuse the earlier answer.
    public static func readLabel(
        nutrition: Data, front: Data, barcode: String, language: String,
        service: AIService, cache: AIResultCache = AIResultCache()
    ) async throws -> LabelOutcome {
        let model = service.settings.model(for: .label)
        let day = DayKey.make(.now)
        let key = AIResultCache.key(parts: [Data(AIFeature.label.rawValue.utf8), Data(language.utf8), Data(model.utf8),
                                            Data(PromptLibrary.version.utf8), nutrition, front])
        cache.purge(keeping: day)
        if let hit = cache.value(ProductLabel.self, key: key, day: day) {
            return outcome(hit.value, barcode: barcode, model: hit.model, cost: 0, fromCache: true)
        }
        let request = AIRequest(
            system: PromptLibrary.load("label")
                .replacingOccurrences(of: "{{LANGUAGE_NAME}}", with: language == "ar" ? "Arabic" : "English"),
            userText: "Read this product label. Barcode: \(barcode).",
            images: [nutrition, front],
            schema: ProductLabel.schema,
            schemaName: "product_label",
            maxOutputTokens: 2048
        )
        let result = try await service.run(ProductLabel.self, request: request, feature: .label)
        cache.store(result.value, model: result.model, key: key, day: day)
        let cost = PriceTable.estimatedCost(of: result.usage, model: result.model, overrides: PriceTable.overrides())
        return outcome(result.value, barcode: barcode, model: result.model, cost: cost, fromCache: false)
    }

    private static func outcome(_ label: ProductLabel, barcode: String, model: String, cost: Double?,
                                fromCache: Bool) -> LabelOutcome {
        LabelOutcome(info: label.readable ? label.info(barcode: barcode) : nil, notes: label.notes,
                     model: model, estimatedCost: cost, fromCache: fromCache)
    }
}

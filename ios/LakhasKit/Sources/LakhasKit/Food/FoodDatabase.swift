import Foundation

/// One food in the bundled DB (ADR-021): per-100 g values as eaten, plus common portions.
public struct FoodEntry: Codable, Sendable, Identifiable, Equatable {
    public struct Portion: Codable, Sendable, Equatable, Hashable {
        public let labelAr: String
        public let labelEn: String
        public let grams: Double

        public func label(language: String) -> String { language == "ar" ? labelAr : labelEn }
    }

    public struct Per100: Codable, Sendable, Equatable {
        public let kcal: Double
        public let protein: Double
        public let carbs: Double
        public let fat: Double
    }

    public let id: String
    public let nameAr: String
    public let nameEn: String
    public let aliasesAr: [String]
    public let aliasesEn: [String]
    public let category: String
    public let per100: Per100
    public let portions: [Portion]
    /// `usda` (real values) or `curated_estimate` (hand-built Egyptian/Arab dishes).
    public let source: String

    public var macros: Macros {
        Macros(kcal: per100.kcal, protein: per100.protein, carbs: per100.carbs, fat: per100.fat)
    }

    public var isCurated: Bool { source == "curated_estimate" }

    public func name(language: String) -> String { language == "ar" ? nameAr : nameEn }
}

/// Bundled, read-only food database with spelling-tolerant Arabic/English search.
public final class FoodDatabase: @unchecked Sendable {
    public static let shared = FoodDatabase()

    public let foods: [FoodEntry]
    private let byID: [String: FoodEntry]
    /// Normalized search terms per food (names + aliases).
    private let terms: [[String]]

    private struct File: Decodable {
        let foods: [FoodEntry]
    }

    public convenience init() {
        let url = Bundle.module.url(forResource: "foods", withExtension: "json")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let foods = data.flatMap { try? JSONDecoder().decode(File.self, from: $0).foods } ?? []
        self.init(foods: foods)
    }

    public init(foods: [FoodEntry]) {
        self.foods = foods
        byID = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        terms = foods.map { food in
            ([food.nameAr, food.nameEn] + food.aliasesAr + food.aliasesEn).map(TextNormalizer.normalize)
        }
    }

    public func food(id: String) -> FoodEntry? { byID[id] }

    /// Best matches first. Curated Egyptian dishes win ties, then shorter names.
    public func search(_ query: String, limit: Int = 30) -> [FoodEntry] {
        let needle = TextNormalizer.normalize(query)
        guard !needle.isEmpty else { return [] }
        var scored: [(score: Int, index: Int)] = []
        for (index, foodTerms) in terms.enumerated() {
            let score = foodTerms.map { Self.score(term: $0, needle: needle) }.max() ?? 0
            if score > 0 { scored.append((score, index)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let left = foods[lhs.index], right = foods[rhs.index]
            if left.isCurated != right.isCurated { return left.isCurated }
            return left.nameEn.count < right.nameEn.count
        }
        return scored.prefix(limit).map { foods[$0.index] }
    }

    /// Candidates for the AI prompt: the matches for each word of a free-text description.
    public func candidates(for text: String, limit: Int = 25) -> [FoodEntry] {
        var seen = Set<String>()
        var result: [FoodEntry] = []
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "،" }).map(String.init)
        // Arabic attaches "and" (و) to the next word: "فول وطعمية" → also try "طعمية".
        let variants = words.flatMap { word -> [String] in
            word.hasPrefix("و") && word.count > 3 ? [word, String(word.dropFirst())] : [word]
        }
        for chunk in [text] + variants {
            for food in search(chunk, limit: 5) where seen.insert(food.id).inserted {
                result.append(food)
                if result.count >= limit { return result }
            }
        }
        return result
    }

    static func score(term: String, needle: String) -> Int {
        if term == needle { return 100 }
        if term.hasPrefix(needle) { return 80 }
        if term.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 60 }
        if needle.count >= 3, term.contains(needle) { return 40 }
        return 0
    }
}

/// Search normalization (ADR-021): Arabic letter variants and diacritics folded, Latin lowercased.
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.lowercased().unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x0640:     // tashkeel, superscript alef, tatweel
                continue
            case 0x0623, 0x0625, 0x0622, 0x0671:     // أ إ آ ٱ → ا
                result.unicodeScalars.append("\u{0627}")
            case 0x0649:                              // ى → ي
                result.unicodeScalars.append("\u{064A}")
            case 0x0629:                              // ة → ه
                result.unicodeScalars.append("\u{0647}")
            case 0x0624:                              // ؤ → و
                result.unicodeScalars.append("\u{0648}")
            case 0x0626:                              // ئ → ي
                result.unicodeScalars.append("\u{064A}")
            case 0x0027, 0x2019, 0x002D, 0x0028, 0x0029:   // ' ’ - ( )
                result.unicodeScalars.append(" ")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result.split(separator: " ").joined(separator: " ")
    }
}

import Foundation
import SwiftData

/// Placeholder plate per dish category (PROJECT_PROMPT.md §4.9): no AI images.
public enum DishCategory: String, Codable, Sendable, CaseIterable {
    case beans, eggs, dairy, bread, rice, stew, grill, fish, salad, soup, pasta, sweet, fruit, snack, drink
}

/// One curated Explore dish (ADR-026). Ingredient names and per-100 g values come from the
/// bundled food DB at build time (`ios/data/scripts/build-explore.mjs`); amounts are for
/// `servings`. Every value is an estimate.
public struct ExploreDish: Codable, Sendable, Identifiable, Hashable {
    public struct Ingredient: Codable, Sendable, Equatable {
        public let foodId: String
        public let nameAr: String
        public let nameEn: String
        public let grams: Double
        public let measureAr: String
        public let measureEn: String
        public let per100: FoodEntry.Per100

        public var macros: Macros {
            Macros(kcal: per100.kcal, protein: per100.protein, carbs: per100.carbs, fat: per100.fat)
        }

        public func measure(language: String) -> String { language == "ar" ? measureAr : measureEn }
    }

    public let id: String
    public let nameAr: String
    public let nameEn: String
    public let aliasesAr: [String]
    public let aliasesEn: [String]
    public let category: String
    public let mealTypes: [String]
    public let goals: [String]
    public let servings: Int
    /// Position in the curated list (the library's own order).
    public let order: Int
    public let ingredients: [Ingredient]

    public static func == (lhs: ExploreDish, rhs: ExploreDish) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var dishCategory: DishCategory { DishCategory(rawValue: category) ?? .rice }
    public var meals: [MealType] { mealTypes.compactMap(MealType.init(rawValue:)) }
    public var goalTags: [Goal] { goals.compactMap(Goal.init(rawValue:)) }

    public func name(language: String) -> String { language == "ar" ? nameAr : nameEn }

    /// grams × per-100 g over all ingredients (all servings).
    public var totals: Macros {
        ingredients.reduce(.zero) { sum, item in
            let factor = item.grams / 100
            let per100 = item.macros
            return sum + Macros(kcal: per100.kcal * factor, protein: per100.protein * factor,
                                carbs: per100.carbs * factor, fat: per100.fat * factor)
        }
    }

    public var perServing: Macros {
        let count = Double(max(servings, 1))
        let total = totals
        return Macros(kcal: total.kcal / count, protein: total.protein / count,
                      carbs: total.carbs / count, fat: total.fat / count)
    }

    /// The editable copy shown on the dish screen: DB values, household measures in `language`.
    public func draft(language: String) -> RecipeDraft {
        RecipeDraft(
            titleAr: nameAr, titleEn: nameEn, servings: servings,
            ingredients: ingredients.map { item in
                DraftItem(nameAr: item.nameAr, nameEn: item.nameEn, grams: item.grams, per100: item.macros,
                          valueSource: .db, foodDbId: item.foodId, measure: item.measure(language: language))
            },
            estimated: true, source: .explore, language: language
        )
    }

    /// The meal type to preselect: the time of day's when the dish fits it, else the dish's first.
    public func suggestedMealType(at date: Date = .now, calendar: Calendar = .current) -> MealType {
        let now = MealType.suggested(for: date, calendar: calendar)
        return meals.contains(now) ? now : (meals.first ?? now)
    }
}

/// How the Explore list is ordered.
public enum ExploreSort: String, CaseIterable, Sendable, Identifiable {
    case recommended, lowestCalories, highestProtein, favorites, mostLiked

    public var id: String { rawValue }
}

/// The user's own 👍 / 👎 for a dish (local only; there are no shared votes, ADR-020).
public enum DishRating: Int, Codable, Sendable {
    case disliked = -1, none = 0, liked = 1
}

/// A plain copy of a dish's local preferences, for sorting.
public struct DishPreferenceState: Equatable, Sendable {
    public var isFavorite: Bool
    public var rating: DishRating
    public var favoritedAt: Date?

    public static let none = DishPreferenceState(isFavorite: false, rating: .none, favoritedAt: nil)

    public init(isFavorite: Bool, rating: DishRating, favoritedAt: Date?) {
        self.isFavorite = isFavorite
        self.rating = rating
        self.favoritedAt = favoritedAt
    }
}

/// The bundled, read-only Explore library (ADR-026) with filters, spelling-tolerant search and sorting.
public final class ExploreLibrary: @unchecked Sendable {
    public static let shared = ExploreLibrary()

    public let dishes: [ExploreDish]
    private let byID: [String: ExploreDish]
    /// Normalized names and aliases per dish.
    private let nameTerms: [[String]]
    /// Normalized ingredient names per dish (weaker matches).
    private let ingredientTerms: [[String]]

    private struct File: Decodable {
        let dishes: [ExploreDish]
    }

    public convenience init() {
        let url = Bundle.module.url(forResource: "dishes", withExtension: "json")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let dishes = data.flatMap { try? JSONDecoder().decode(File.self, from: $0).dishes } ?? []
        self.init(dishes: dishes)
    }

    public init(dishes: [ExploreDish]) {
        self.dishes = dishes.sorted { $0.order < $1.order }
        byID = Dictionary(dishes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        nameTerms = self.dishes.map { dish in
            ([dish.nameAr, dish.nameEn] + dish.aliasesAr + dish.aliasesEn).map(Self.searchKey)
        }
        ingredientTerms = self.dishes.map { dish in
            dish.ingredients.flatMap { [$0.nameAr, $0.nameEn] }.map(Self.searchKey)
        }
    }

    public func dish(id: String) -> ExploreDish? { byID[id] }

    /// Dishes that pass the filters and match `query`. With a query, better matches come first.
    public func dishes(matching query: String = "", goal: Goal? = nil, mealType: MealType? = nil) -> [ExploreDish] {
        scored(query, goal: goal, mealType: mealType).map(\.dish)
    }

    /// The list as shown: filtered and sorted. While searching, better matches come first and
    /// `sort` orders the dishes that match equally well ("koshari" shows Koshary before the
    /// small koshary even when the small one suits the goal better).
    public func ranked(matching query: String = "", goal: Goal? = nil, mealType: MealType? = nil, sort: ExploreSort,
                       userGoal: Goal?, preferences: [String: DishPreferenceState]) -> [ExploreDish] {
        let matches = scored(query, goal: goal, mealType: mealType)
        let sorted = Self.sorted(matches.map(\.dish), by: sort, goal: userGoal, preferences: preferences)
        guard !Self.searchKey(query).isEmpty else { return sorted }
        let scores = Dictionary(matches.map { ($0.dish.id, $0.score) }, uniquingKeysWith: { first, _ in first })
        return sorted.enumerated()
            .sorted { lhs, rhs in
                let left = scores[lhs.element.id] ?? 0, right = scores[rhs.element.id] ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func scored(_ query: String, goal: Goal?, mealType: MealType?) -> [(score: Int, dish: ExploreDish)] {
        let needle = Self.searchKey(query)
        var scored: [(score: Int, dish: ExploreDish)] = []
        for (index, dish) in dishes.enumerated() {
            if let goal, !dish.goalTags.contains(goal) { continue }
            if let mealType, !dish.meals.contains(mealType) { continue }
            let score = needle.isEmpty ? 1 : Self.score(names: nameTerms[index], ingredients: ingredientTerms[index], needle: needle)
            if score > 0 { scored.append((score, dish)) }
        }
        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.dish.order < rhs.dish.order
        }
        return scored
    }

    /// Orders dishes for the list. Sorting is stable: ties keep the incoming order.
    public static func sorted(_ dishes: [ExploreDish], by sort: ExploreSort, goal: Goal?,
                              preferences: [String: DishPreferenceState]) -> [ExploreDish] {
        let prefs = { (dish: ExploreDish) in preferences[dish.id] ?? .none }
        let keyed = dishes.enumerated().map { (offset: $0.offset, dish: $0.element) }
        func ordered(_ before: (ExploreDish, ExploreDish) -> Bool?) -> [ExploreDish] {
            keyed.sorted { lhs, rhs in before(lhs.dish, rhs.dish) ?? (lhs.offset < rhs.offset) }.map(\.dish)
        }
        func recommended(_ lhs: ExploreDish, _ rhs: ExploreDish) -> Bool? {
            let left = recommendationScore(lhs, goal: goal, preference: prefs(lhs))
            let right = recommendationScore(rhs, goal: goal, preference: prefs(rhs))
            return left == right ? nil : left > right
        }
        switch sort {
        case .recommended:
            return ordered(recommended)
        case .lowestCalories:
            return ordered { lhs, rhs in
                let left = lhs.perServing.kcal, right = rhs.perServing.kcal
                return left == right ? nil : left < right
            }
        case .highestProtein:
            return ordered { lhs, rhs in
                let left = lhs.perServing.protein, right = rhs.perServing.protein
                return left == right ? nil : left > right
            }
        case .favorites:
            return ordered { lhs, rhs in
                let left = prefs(lhs), right = prefs(rhs)
                if left.isFavorite != right.isFavorite { return left.isFavorite }
                if left.isFavorite, let leftDate = left.favoritedAt, let rightDate = right.favoritedAt, leftDate != rightDate {
                    return leftDate > rightDate
                }
                return recommended(lhs, rhs)
            }
        case .mostLiked:
            return ordered { lhs, rhs in
                let left = prefs(lhs), right = prefs(rhs)
                if left.rating != right.rating { return left.rating.rawValue > right.rating.rawValue }
                if left.isFavorite != right.isFavorite { return left.isFavorite }
                return recommended(lhs, rhs)
            }
        }
    }

    /// "Recommended for my goal": dishes tagged with the goal first; then, for losing, fewer
    /// calories and more protein per calorie; for maintaining, close to 550 kcal with good
    /// protein; for gaining, more calories and protein. My 👍 and favorites move a dish up,
    /// a 👎 moves it to the end. No goal counts as maintain.
    public static func recommendationScore(_ dish: ExploreDish, goal: Goal?, preference: DishPreferenceState = .none) -> Double {
        let goal = goal ?? .maintain
        let macros = dish.perServing
        let proteinShare = macros.kcal > 0 ? macros.protein * 4 / macros.kcal : 0
        var score = dish.goalTags.contains(goal) ? 1000.0 : 0
        switch goal {
        case .lose: score += 200 * proteinShare - macros.kcal / 5
        case .maintain: score += 200 * proteinShare - abs(macros.kcal - 550) / 5
        case .gain: score += 100 * proteinShare + macros.kcal / 5
        }
        switch preference.rating {
        case .liked: score += 50
        case .disliked: score -= 5000
        case .none: break
        }
        if preference.isFavorite { score += 50 }
        return score
    }

    // MARK: Search

    /// `TextNormalizer` plus the Arabic article: "الكشري" and "كشري" match.
    static func searchKey(_ text: String) -> String {
        TextNormalizer.normalize(text)
            .split(separator: " ")
            .map { word in
                word.hasPrefix("ال") && word.count > 3 ? String(word.dropFirst(2)) : String(word)
            }
            .joined(separator: " ")
    }

    static func score(names: [String], ingredients: [String], needle: String) -> Int {
        let best = names.map { FoodDatabase.score(term: $0, needle: needle) }.max() ?? 0
        if best > 0 { return best }
        // Every word of the query starts a word of the same name: "chicken rice".
        let words = needle.split(separator: " ")
        if words.count > 1, names.contains(where: { term in
            let termWords = term.split(separator: " ")
            return words.allSatisfy { word in termWords.contains { $0.hasPrefix(word) } }
        }) {
            return 50
        }
        // An ingredient: "عدس" finds the lentil soup and mujaddara.
        let ingredient = ingredients.map { FoodDatabase.score(term: $0, needle: needle) }.max() ?? 0
        return ingredient >= 60 ? 20 : 0
    }
}

/// Logging and saving from Explore. Nothing here calls an AI provider (PROJECT_PROMPT.md §4.5).
public enum ExploreLog {
    public static let portionsRange: ClosedRange<Double> = 0.5...5

    /// Logs `portions` servings of the (possibly edited) dish as one meal titled with its name.
    @discardableResult
    public static func log(_ draft: RecipeDraft, portions: Double = 1, mealType: MealType, at date: Date = .now,
                           language: String, in context: ModelContext) -> Meal {
        let meal = Meal(loggedAt: date, mealType: mealType, source: .explore, title: draft.title(language: language))
        context.insert(meal)
        meal.append(draft.servingItems(portions: portions).map { $0.makeMealItem() })
        return meal
    }

    /// Saves the dish to My Recipes, linked to the Explore dish it came from.
    @discardableResult
    public static func saveToRecipes(_ draft: RecipeDraft, dishId: String, in context: ModelContext, now: Date = .now) -> Recipe {
        let recipe = Recipe.insert(draft, in: context, now: now)
        recipe.exploreDishId = dishId
        return recipe
    }
}

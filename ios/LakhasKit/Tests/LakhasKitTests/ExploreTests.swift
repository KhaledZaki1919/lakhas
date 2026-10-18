import Foundation
import SwiftData
import Testing
@testable import LakhasKit

struct ExploreLibraryTests {
    private let library = ExploreLibrary.shared

    @Test func bundledLibraryLoadsAtLeastSixtyDishes() {
        #expect(library.dishes.count >= 60)
        #expect(Set(library.dishes.map(\.id)).count == library.dishes.count)
        for type in MealType.allCases {
            #expect(library.dishes(mealType: type).count >= 10, "\(type)")
        }
        for goal in Goal.allCases {
            #expect(library.dishes(goal: goal).count >= 15, "\(goal)")
        }
    }

    @Test func everyDishIsCompleteAndUsesTheFoodDatabase() throws {
        let db = FoodDatabase.shared
        for dish in library.dishes {
            #expect(!dish.nameAr.isEmpty && !dish.nameEn.isEmpty, "\(dish.id)")
            #expect(DishCategory(rawValue: dish.category) != nil, "\(dish.id)")
            #expect(dish.meals.count == dish.mealTypes.count && !dish.meals.isEmpty, "\(dish.id)")
            #expect(dish.goalTags.count == dish.goals.count && !dish.goalTags.isEmpty, "\(dish.id)")
            #expect(!dish.ingredients.isEmpty, "\(dish.id)")
            for item in dish.ingredients {
                let food = try #require(db.food(id: item.foodId), "\(dish.id): \(item.foodId)")
                #expect(food.per100 == item.per100, "\(dish.id): \(item.foodId)")
                #expect(food.nameAr == item.nameAr && food.nameEn == item.nameEn)
                #expect(item.grams > 0 && !item.measureAr.isEmpty && !item.measureEn.isEmpty, "\(dish.id)")
            }
            #expect((50...1500).contains(dish.perServing.kcal), "\(dish.id): \(dish.perServing.kcal)")
        }
    }

    @Test func perServingIsGramsTimesPer100() throws {
        // 450 g koshary × 156 kcal / 100 g
        let koshary = try #require(library.dish(id: "koshary-medium"))
        #expect(abs(koshary.perServing.kcal - 702) < 0.01)
        // 250 g foul (127) + 110 g bread (254) + 100 g salad (42) + 30 g pickles (16)
        let foul = try #require(library.dish(id: "foul-plate"))
        #expect(abs(foul.perServing.kcal - (317.5 + 279.4 + 42 + 4.8)) < 0.01)
    }

    @Test(arguments: [
        ("كشري", "koshary-medium"), ("كشرى", "koshary-medium"), ("الكشري", "koshary-medium"), ("koshari", "koshary-medium"),
        ("طعميه", "taameya-plate"), ("فلافل", "taameya-plate"), ("falafel", "taameya-plate"),
        ("ملوخيه", "molokhia-chicken-rice"), ("الملوخية", "molokhia-chicken-rice"), ("mulukhiyah", "molokhia-chicken-rice"),
        ("فته", "fattah-meat-plate"), ("كبسه", "kabsa-chicken-plate"), ("شاورمه", "shawarma-sandwich"),
        ("حواوشى", "hawawshi-plate"), ("أم علي", "om-ali-bowl"), ("ام على", "om-ali-bowl"), ("tabouli", "tabbouleh"),
    ])
    func searchToleratesArabicAndEnglishSpellings(query: String, expected: String) {
        #expect(library.dishes(matching: query).contains { $0.id == expected }, "\(query)")
        #expect(library.dishes(matching: query).prefix(3).contains { $0.id == expected }, "\(query)")
    }

    @Test func searchFindsIngredientsAndSeveralWords() {
        #expect(library.dishes(matching: "عدس").contains { $0.id == "lentil-soup-bowl" })
        #expect(library.dishes(matching: "chicken rice").contains { $0.id == "grilled-chicken-rice" })
        #expect(library.dishes(matching: "zzzz").isEmpty)
    }

    @Test func filtersCombineWithSearch() {
        let breakfastFoul = library.dishes(matching: "فول", goal: .lose, mealType: .breakfast)
        #expect(!breakfastFoul.isEmpty)
        #expect(breakfastFoul.allSatisfy { $0.meals.contains(.breakfast) && $0.goalTags.contains(.lose) })
        #expect(!breakfastFoul.contains { $0.id == "foul-plate" })   // tagged maintain / gain
    }
}

struct ExploreSortTests {
    private let library = ExploreLibrary.shared

    @Test func lowestCaloriesAndHighestProtein() {
        let all = library.dishes
        let byKcal = ExploreLibrary.sorted(all, by: .lowestCalories, goal: nil, preferences: [:])
        #expect(zip(byKcal, byKcal.dropFirst()).allSatisfy { $0.perServing.kcal <= $1.perServing.kcal })
        let byProtein = ExploreLibrary.sorted(all, by: .highestProtein, goal: nil, preferences: [:])
        #expect(zip(byProtein, byProtein.dropFirst()).allSatisfy { $0.perServing.protein >= $1.perServing.protein })
        #expect(byKcal.count == all.count && byProtein.count == all.count)
    }

    @Test(arguments: Goal.allCases)
    func recommendedPutsDishesTaggedForTheGoalFirst(goal: Goal) {
        let sorted = ExploreLibrary.sorted(library.dishes, by: .recommended, goal: goal, preferences: [:])
        let tagged = library.dishes(goal: goal).count
        #expect(sorted.prefix(tagged).allSatisfy { $0.goalTags.contains(goal) })
        #expect(sorted.dropFirst(tagged).allSatisfy { !$0.goalTags.contains(goal) })
    }

    @Test func recommendedForLosingPrefersLeanDishes() throws {
        let fish = try #require(library.dish(id: "grilled-fish-salad"))
        let foul = try #require(library.dish(id: "foul-light"))
        let lose = ExploreLibrary.sorted([foul, fish], by: .recommended, goal: .lose, preferences: [:])
        #expect(lose.first?.id == "grilled-fish-salad")   // fewer kcal, far more protein per kcal

        let fattah = try #require(library.dish(id: "fattah-meat-plate"))
        let kebab = try #require(library.dish(id: "kebab-kofta-rice"))
        let gain = ExploreLibrary.sorted([kebab, fattah], by: .recommended, goal: .gain, preferences: [:])
        #expect(gain.first?.id == "fattah-meat-plate")    // more kcal
    }

    @Test func myRatingsAndFavoritesOrderTheList() {
        let three = Array(library.dishes.prefix(3))
        let now = Date(timeIntervalSince1970: 1_000_000)
        let prefs: [String: DishPreferenceState] = [
            three[0].id: DishPreferenceState(isFavorite: false, rating: .disliked, favoritedAt: nil),
            three[1].id: DishPreferenceState(isFavorite: true, rating: .none, favoritedAt: now),
            three[2].id: DishPreferenceState(isFavorite: false, rating: .liked, favoritedAt: nil),
        ]
        let liked = ExploreLibrary.sorted(three, by: .mostLiked, goal: nil, preferences: prefs)
        #expect(liked.map(\.id) == [three[2].id, three[1].id, three[0].id])
        let favorites = ExploreLibrary.sorted(three, by: .favorites, goal: nil, preferences: prefs)
        #expect(favorites.first?.id == three[1].id)
        // A 👎 sends a dish to the end of "recommended" too.
        let recommended = ExploreLibrary.sorted(three, by: .recommended, goal: nil, preferences: prefs)
        #expect(recommended.last?.id == three[0].id)
    }
}

@MainActor
struct ExploreStoreTests {
    @Test func preferencesToggleAndPersist() throws {
        let context = ModelContext(try LakhasStore.makeContainer(inMemory: true))
        let preference = DishPreference.findOrInsert("koshary-medium", in: context)
        preference.toggleFavorite()
        preference.rate(.liked)
        try context.save()

        let found = try #require(DishPreference.find("koshary-medium", in: context))
        #expect(found.isFavorite && found.favoritedAt != nil && found.rating == .liked)
        #expect(DishPreference.findOrInsert("koshary-medium", in: context) === found)
        found.rate(.liked)          // same rating again clears it
        #expect(found.rating == .none)
        found.rate(.disliked)
        #expect(found.rating == .disliked)
        found.toggleFavorite()
        #expect(!found.isFavorite && found.favoritedAt == nil)
    }

    @Test func loggingUsesTheEditedDraftAndPortions() throws {
        let context = ModelContext(try LakhasStore.makeContainer(inMemory: true))
        let dish = try #require(ExploreLibrary.shared.dish(id: "foul-plate"))
        var draft = dish.draft(language: "en")
        #expect(draft.source == .explore && draft.estimated)
        #expect(draft.ingredients.first?.measure == "plate")
        #expect(draft.ingredients.allSatisfy { $0.valueSource == .db && $0.foodDbId != nil })
        draft.ingredients[1].grams = 55   // half a loaf instead of one

        let meal = ExploreLog.log(draft, portions: 1.5, mealType: .breakfast, language: "en", in: context)
        try context.save()
        #expect(meal.source == .explore && meal.mealType == .breakfast)
        #expect(meal.title == "Foul with oil and baladi bread")
        #expect(meal.orderedItems.map(\.grams) == [375, 82.5, 150, 45])
        #expect(abs(meal.totals.kcal - draft.totals.kcal * 1.5) < 0.5)
    }

    @Test func savingToMyRecipesKeepsTheDishLink() throws {
        let context = ModelContext(try LakhasStore.makeContainer(inMemory: true))
        let dish = try #require(ExploreLibrary.shared.dish(id: "tabbouleh"))
        var draft = dish.draft(language: "ar")
        draft.setServings(2, scaleIngredients: true)
        let recipe = ExploreLog.saveToRecipes(draft, dishId: dish.id, in: context)
        try context.save()

        let saved = try context.fetch(FetchDescriptor<Recipe>())
        #expect(saved.count == 1)
        #expect(recipe.exploreDishId == "tabbouleh" && recipe.source == .explore)
        #expect(recipe.servings == 2 && recipe.orderedIngredients.count == dish.ingredients.count)
        #expect(abs(recipe.draft.perServing.kcal - dish.perServing.kcal) < 1)
        #expect(recipe.orderedIngredients.first?.measure == "حزمة بقدونس")
    }
}

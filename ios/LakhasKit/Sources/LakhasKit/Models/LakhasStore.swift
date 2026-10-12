import Foundation
import NutritionMath
import SwiftData

/// Creates the SwiftData container in the resolved store location (ADR-014) and applies
/// file protection to the store files (PROJECT_PROMPT.md §3.4).
public enum LakhasStore {
    public static let schema = Schema([UserProfile.self, GoalOverride.self, Meal.self, MealItem.self])

    public static func makeContainer(
        location: StoreLocation = AppGroupResolver.resolve(), inMemory: Bool = false
    ) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let url = location.directory.appendingPathComponent("Lakhas.store")
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
        for suffix in ["", "-wal", "-shm"] {
            FileProtection.apply(to: URL(fileURLWithPath: url.path + suffix))
        }
        return container
    }
}

/// Today's targets: computed from the profile, then overridden by "My Goals" where set.
public enum TargetsResolver {
    public static func targets(profile: UserProfile, override: GoalOverride?, on date: Date = .now) -> DailyTargets {
        let computed = NutritionMath.targets(for: profile.bodyProfile(goalWeightKg: override?.goalWeightKg, on: date))
        guard let override else { return computed }
        return DailyTargets(
            bmr: computed.bmr,
            tdee: computed.tdee,
            calories: override.calories ?? computed.calories,
            proteinG: override.proteinG ?? computed.proteinG,
            carbsG: override.carbsG ?? computed.carbsG,
            fatG: override.fatG ?? computed.fatG,
            waterMl: override.waterMl ?? computed.waterMl,
            floorApplied: override.calories == nil && computed.floorApplied,
            fatReduced: override.fatG == nil && computed.fatReduced
        )
    }
}

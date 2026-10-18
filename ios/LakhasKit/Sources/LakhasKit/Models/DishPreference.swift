import Foundation
import SwiftData

/// What the user keeps about one Explore dish, on this device only (ADR-026): a favorite,
/// their own 👍 / 👎, and their own photo used as the dish's picture.
@Model
public final class DishPreference {
    @Attribute(.unique) public var dishId: String
    public var isFavorite: Bool
    public var ratingRaw: Int
    public var favoritedAt: Date?
    /// The user's photo of this dish in `MealPhotoStore` (device only).
    public var photoFileName: String?
    public var updatedAt: Date

    public init(dishId: String, now: Date = .now) {
        self.dishId = dishId
        isFavorite = false
        ratingRaw = DishRating.none.rawValue
        updatedAt = now
    }

    public var rating: DishRating { DishRating(rawValue: ratingRaw) ?? .none }

    public var state: DishPreferenceState {
        DishPreferenceState(isFavorite: isFavorite, rating: rating, favoritedAt: favoritedAt)
    }

    public func toggleFavorite(now: Date = .now) {
        isFavorite.toggle()
        favoritedAt = isFavorite ? now : nil
        updatedAt = now
    }

    /// Tapping the current rating again clears it.
    public func rate(_ rating: DishRating, now: Date = .now) {
        ratingRaw = (self.rating == rating ? DishRating.none : rating).rawValue
        updatedAt = now
    }

    public static func find(_ dishId: String, in context: ModelContext) -> DishPreference? {
        var descriptor = FetchDescriptor<DishPreference>(predicate: #Predicate { $0.dishId == dishId })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The dish's preference row, inserted on first use.
    public static func findOrInsert(_ dishId: String, in context: ModelContext, now: Date = .now) -> DishPreference {
        if let existing = find(dishId, in: context) { return existing }
        let preference = DishPreference(dishId: dishId, now: now)
        context.insert(preference)
        return preference
    }
}

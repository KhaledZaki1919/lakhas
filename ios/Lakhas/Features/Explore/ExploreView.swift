import LakhasKit
import SwiftData
import SwiftUI

/// Explore (PROJECT_PROMPT.md §4.5, ADR-026): the bundled dish library with meal and goal
/// filters, spelling-tolerant search and sorting. Favorites and 👍 / 👎 are this device's only.
struct ExploreView: View {
    @Query private var preferences: [DishPreference]
    @Query private var profiles: [UserProfile]
    @State private var search = ""
    @State private var mealFilter: MealType?
    @State private var goalFilter: Goal?
    @State private var sort: ExploreSort = .recommended

    private let library = ExploreLibrary.shared
    private let format = AppFormat.current

    private var preferenceStates: [String: DishPreferenceState] {
        Dictionary(preferences.map { ($0.dishId, $0.state) }, uniquingKeysWith: { first, _ in first })
    }

    private var shown: [ExploreDish] {
        library.ranked(matching: search, goal: goalFilter, mealType: mealFilter, sort: sort,
                       userGoal: profiles.first?.goal, preferences: preferenceStates)
    }

    var body: some View {
        let states = preferenceStates
        let photos = Dictionary(preferences.compactMap { pref in pref.photoFileName.map { (pref.dishId, $0) } },
                                uniquingKeysWith: { first, _ in first })
        let dishes = shown
        List {
            Section {
                filters
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if dishes.isEmpty {
                ContentUnavailableView {
                    Label("tab.explore", systemImage: "safari")
                } description: {
                    Text("explore.empty")
                }
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(dishes) { dish in
                    NavigationLink(value: dish) {
                        ExploreRow(dish: dish, state: states[dish.id] ?? .none, photo: photos[dish.id], format: format)
                    }
                    .accessibilityIdentifier("ax.explore.dish")
                }
            } footer: {
                if !dishes.isEmpty { Text("explore.estimate") }
            }
        }
        .searchable(text: $search, prompt: Text("explore.search"))
        .navigationTitle("tab.explore")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("explore.sort", selection: $sort) {
                        ForEach(ExploreSort.allCases) { Text($0.titleKey).tag($0) }
                    }
                } label: {
                    Label("explore.sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("ax.explore.sort")
            }
        }
        .navigationDestination(for: ExploreDish.self) { DishDetailView(dish: $0) }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    FilterChip(titleKey: "explore.filter.allMeals", isSelected: mealFilter == nil) { mealFilter = nil }
                        .accessibilityIdentifier("ax.explore.meal.all")
                    ForEach(MealType.allCases) { type in
                        FilterChip(titleKey: type.titleKey, isSelected: mealFilter == type) {
                            mealFilter = mealFilter == type ? nil : type
                        }
                        .accessibilityIdentifier("ax.explore.meal.\(type.rawValue)")
                    }
                }
                .padding(.horizontal, Theme.Space.xxs)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    FilterChip(titleKey: "explore.filter.allGoals", isSelected: goalFilter == nil) { goalFilter = nil }
                        .accessibilityIdentifier("ax.explore.goal.all")
                    ForEach(Goal.allCases, id: \.self) { goal in
                        FilterChip(titleKey: goal.exploreKey, isSelected: goalFilter == goal) {
                            goalFilter = goalFilter == goal ? nil : goal
                        }
                        .accessibilityIdentifier("ax.explore.goal.\(goal.rawValue)")
                    }
                }
                .padding(.horizontal, Theme.Space.xxs)
            }
            Label(sort.titleKey, systemImage: "arrow.up.arrow.down")
                .font(.caption)
                .foregroundStyle(Theme.Palette.muted)
                .padding(.horizontal, Theme.Space.xxs)
        }
        .padding(.vertical, Theme.Space.xxs)
    }
}

/// Capsule filter (`radius.chip`): `primary` when selected.
struct FilterChip: View {
    let titleKey: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, Theme.Space.sm)
                .frame(minHeight: 36)
                .foregroundStyle(isSelected ? Theme.Palette.onPrimary : Theme.Palette.ink)
                .background(isSelected ? Theme.Palette.primary : Theme.Palette.surface, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.Palette.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ExploreRow: View {
    let dish: ExploreDish
    let state: DishPreferenceState
    let photo: String?
    let format: AppFormat

    var body: some View {
        let macros = dish.perServing
        HStack(spacing: Theme.Space.sm) {
            DishImage(category: dish.dishCategory, photoFileName: photo, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: dish.name(language: format.language))
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                Text(verbatim: detail(macros))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.muted)
                    .lineLimit(1)
                HStack(spacing: Theme.Space.xxs) {
                    if state.isFavorite {
                        Image(systemName: "heart.fill").foregroundStyle(Theme.Palette.accent)
                            .accessibilityLabel(Text("explore.favorite"))
                    }
                    if state.rating == .liked {
                        Image(systemName: "hand.thumbsup.fill").foregroundStyle(Theme.Palette.primary)
                            .accessibilityLabel(Text("explore.like"))
                    } else if state.rating == .disliked {
                        Image(systemName: "hand.thumbsdown.fill").foregroundStyle(Theme.Palette.muted)
                            .accessibilityLabel(Text("explore.dislike"))
                    }
                    Text(verbatim: dish.goalTags.map { String(localized: $0.exploreResource) }.joined(separator: " · "))
                        .foregroundStyle(Theme.Palette.primary)
                }
                .font(.caption2.weight(.semibold))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: format.number(Int(macros.kcal.rounded()))).font(.headline.monospacedDigit())
                Text("unit.kcal").font(.caption2).foregroundStyle(Theme.Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ macros: Macros) -> String {
        let meals = dish.meals.map { String(localized: $0.resource) }.joined(separator: format.language == "ar" ? "، " : ", ")
        let protein = String(localized: "explore.row.protein \(format.number(Int(macros.protein.rounded())))")
        return [protein, meals].joined(separator: " · ")
    }
}

extension ExploreSort {
    var titleKey: LocalizedStringKey {
        switch self {
        case .recommended: "explore.sort.recommended"
        case .lowestCalories: "explore.sort.lowestCalories"
        case .highestProtein: "explore.sort.highestProtein"
        case .favorites: "explore.sort.favorites"
        case .mostLiked: "explore.sort.mostLiked"
        }
    }
}

extension Goal {
    /// Short chip label ("Lose" rather than "Lose weight").
    var exploreKey: LocalizedStringKey {
        switch self {
        case .lose: "explore.goal.lose"
        case .maintain: "explore.goal.maintain"
        case .gain: "explore.goal.gain"
        }
    }

    var exploreResource: LocalizedStringResource {
        switch self {
        case .lose: "explore.goal.lose"
        case .maintain: "explore.goal.maintain"
        case .gain: "explore.goal.gain"
        }
    }
}

extension MealType {
    var resource: LocalizedStringResource {
        switch self {
        case .breakfast: "meal.breakfast"
        case .lunch: "meal.lunch"
        case .dinner: "meal.dinner"
        case .snack: "meal.snack"
        }
    }
}

import LakhasKit
import SwiftData
import SwiftUI

/// Search the bundled food DB (no key): Egyptian dishes first, spelling-tolerant (ADR-021).
struct FoodSearchView: View {
    let onPick: (FoodEntry, Double) -> Void

    @State private var query = ""
    @State private var selected: FoodEntry?
    @Environment(\.dismiss) private var dismiss

    private let database = FoodDatabase.shared
    private let format = AppFormat.current

    private var results: [FoodEntry] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? Array(database.foods.filter(\.isCurated).prefix(40))
            : database.search(query)
    }

    var body: some View {
        List(results) { food in
            Button {
                selected = food
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: food.name(language: format.language))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(verbatim: String(localized: "search.per100 \(format.number(Int(food.per100.kcal.rounded())))"))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.muted)
                    }
                    Spacer()
                    if food.isCurated {
                        Text("search.estimate")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.muted)
                    }
                }
            }
            .accessibilityIdentifier("ax.search.result")
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("search.prompt"))
        .navigationTitle("search.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.cancel") { dismiss() }
            }
        }
        .sheet(item: $selected) { food in
            PortionPicker(food: food) { grams in
                selected = nil
                onPick(food, grams)
            }
            .presentationDetents([.medium])
        }
    }
}

/// Pick an Egyptian portion (plate, sandwich, loaf…) or type grams.
struct PortionPicker: View {
    let food: FoodEntry
    let onAdd: (Double) -> Void

    @State private var grams: Double
    private let format = AppFormat.current

    init(food: FoodEntry, onAdd: @escaping (Double) -> Void) {
        self.food = food
        self.onAdd = onAdd
        _grams = State(initialValue: food.portions.first?.grams ?? 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !food.portions.isEmpty {
                    Section("search.portions") {
                        ForEach(food.portions, id: \.self) { portion in
                            Button {
                                grams = portion.grams
                            } label: {
                                HStack {
                                    Text(verbatim: portion.label(language: format.language)).foregroundStyle(Theme.Palette.ink)
                                    Spacer()
                                    Text(verbatim: "\(format.number(portion.grams, fractionDigits: 1)) \(String(localized: "unit.g"))")
                                        .foregroundStyle(Theme.Palette.muted)
                                    if portion.grams == grams {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.Palette.primary)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("unit.g", value: $grams, format: .number.precision(.fractionLength(0)).locale(format.locale))
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("ax.portion.grams")
                        Text("unit.g").foregroundStyle(Theme.Palette.muted)
                    }
                } footer: {
                    let kcal = food.per100.kcal * grams / 100
                    Text(verbatim: "\(format.number(Int(kcal.rounded()))) \(String(localized: "unit.kcal"))")
                }
            }
            .navigationTitle(Text(verbatim: food.name(language: format.language)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("search.add") { onAdd(grams) }
                        .disabled(grams <= 0)
                        .accessibilityIdentifier("ax.portion.add")
                }
            }
        }
    }
}

/// Plate-builder (no key, no AI): pick foods from the DB and save them as a meal.
struct PlateBuilderView: View {
    let request: LogRequest
    let onSaved: () -> Void

    @State private var items: [DraftItem] = []
    @State private var showSearch = true

    var body: some View {
        ReviewView(request: request, source: .plate, outcome: nil, items: items, onSaved: onSaved)
            .id(items.map(\.id))
            .sheet(isPresented: $showSearch) {
                NavigationStack {
                    FoodSearchView { food, grams in
                        items.append(DraftItem(food: food, grams: grams))
                        showSearch = false
                    }
                }
            }
    }
}

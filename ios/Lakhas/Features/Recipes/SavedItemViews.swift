import LakhasKit
import SwiftData
import SwiftUI

/// A saved meal: its items and one-tap logging (PROJECT_PROMPT.md §4.3 D).
struct SavedMealDetailView: View {
    let meal: SavedMeal

    @Environment(\.modelContext) private var context
    @State private var title: String
    @State private var mealType: MealType
    @State private var logged = 0
    @State private var showLogged = false

    private let format = AppFormat.current

    init(meal: SavedMeal) {
        self.meal = meal
        _title = State(initialValue: meal.title)
        _mealType = State(initialValue: meal.mealType)
    }

    var body: some View {
        List {
            Section {
                TextField("saved.name", text: $title)
                    .font(.title3.bold())
                    .onSubmit(rename)
                    .accessibilityIdentifier("ax.saved.name")
            }
            Section {
                ForEach(meal.orderedItems) { item in
                    HStack {
                        Text(verbatim: item.name(language: format.language))
                        Spacer()
                        Text(verbatim: "\(format.number(Int(item.grams.rounded())))\(String(localized: "unit.g"))")
                            .foregroundStyle(Theme.Palette.muted)
                        Text(verbatim: format.number(Int(item.totals.kcal.rounded())))
                            .monospacedDigit()
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .font(.callout)
                }
            } header: {
                HStack {
                    Text("review.items")
                    Spacer()
                    Text(verbatim: "\(format.number(Int(meal.totals.kcal.rounded()))) \(String(localized: "unit.kcal"))")
                        .monospacedDigit()
                }
            }
            Section {
                Picker("quickadd.mealType", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.titleKey).tag($0) }
                }
                PrimaryButton(titleKey: "saved.log") { log() }
                    .accessibilityIdentifier("ax.saved.log")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                if showLogged {
                    Label("recipes.detail.logged", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Palette.primary)
                }
            }
        }
        .navigationTitle("saved.title")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: rename)
        .sensoryFeedback(.success, trigger: logged)
    }

    private func rename() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != meal.title else { return }
        meal.title = trimmed
        try? context.save()
    }

    private func log() {
        rename()
        meal.log(at: .now, mealType: mealType, in: context)
        try? context.save()
        logged += 1
        showLogged = true
    }
}

/// Log sheet → Saved meal: one tap logs it into the day being viewed.
struct SavedMealPickerView: View {
    let request: LogRequest
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \SavedMeal.lastUsedAt, order: .reverse) private var meals: [SavedMeal]
    @State private var logged = 0

    private let format = AppFormat.current

    var body: some View {
        List {
            if meals.isEmpty {
                ContentUnavailableView {
                    Label("log.saved", systemImage: "bookmark")
                } description: {
                    Text("recipes.empty.meals")
                }
            }
            ForEach(meals) { meal in
                Button {
                    log(meal)
                } label: {
                    HubRow(photo: meal.photoFileName, symbol: "bookmark", title: meal.title,
                           detail: String(localized: "recipes.hub.items \(format.number(meal.items.count))"),
                           kcal: meal.totals.kcal, format: format)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ax.saved.pick")
            }
        }
        .navigationTitle("log.saved")
        .sensoryFeedback(.success, trigger: logged)
    }

    private func log(_ meal: SavedMeal) {
        meal.log(at: request.date, mealType: request.mealType ?? MealType.suggested(for: request.date), in: context)
        try? context.save()
        logged += 1
        onDone()
    }
}

/// A product from the local library: values per 100 g and logging an amount through review.
struct ProductDetailView: View {
    let product: Product

    @State private var grams: Double
    @State private var review: DraftBox?
    @State private var logged = false

    private let format = AppFormat.current

    init(product: Product) {
        self.product = product
        _grams = State(initialValue: product.servingGrams ?? 100)
    }

    var body: some View {
        List {
            Section {
                Text(verbatim: product.info.name(language: format.language)).font(.title3.bold())
                if let brand = product.brand {
                    Text(verbatim: brand).foregroundStyle(Theme.Palette.muted)
                }
                Text(verbatim: product.barcode)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.Palette.muted)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Section {
                value("quickadd.kcal", product.kcalPer100, unit: "unit.kcal")
                value("macro.protein", product.proteinPer100, unit: "unit.g")
                value("macro.carbs", product.carbsPer100, unit: "unit.g")
                value("macro.fat", product.fatPer100, unit: "unit.g")
            } header: {
                Text("recipes.hub.per100")
            }
            Section {
                HStack {
                    Text("review.grams")
                    Spacer()
                    TextField("unit.g", value: $grams, format: .number.precision(.fractionLength(0)).locale(format.locale))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("unit.g").foregroundStyle(Theme.Palette.muted)
                }
                PrimaryButton(titleKey: "product.log", isEnabled: grams > 0) {
                    review = DraftBox(items: [product.info.draftItem(grams: grams)])
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if logged {
                    Label("recipes.detail.logged", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.Palette.primary)
                }
            }
        }
        .navigationTitle("recipes.hub.product")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $review) { box in
            ReviewView(request: LogRequest(date: .now, mealType: nil), source: .barcode, outcome: nil, items: box.items) {
                review = nil
                logged = true
            }
        }
    }

    private func value(_ key: LocalizedStringKey, _ number: Double, unit: LocalizedStringKey) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(verbatim: format.number(number, fractionDigits: number < 10 ? 1 : 0)).monospacedDigit()
            Text(unit).foregroundStyle(Theme.Palette.muted)
        }
    }
}

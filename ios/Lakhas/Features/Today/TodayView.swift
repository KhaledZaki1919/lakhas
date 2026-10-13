import LakhasKit
import SwiftData
import SwiftUI

/// Today (PROJECT_PROMPT.md §4.2): ring, labeled macro bars, meals by group, date strip.
struct TodayView: View {
    let onLog: (LogRequest) -> Void

    @Query private var profiles: [UserProfile]
    @Query private var overrides: [GoalOverride]
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    private let format = AppFormat.current

    var body: some View {
        Group {
            if let profile = profiles.first {
                DayContent(
                    dayKey: DayKey.make(selectedDate),
                    date: selectedDate,
                    targets: TargetsResolver.targets(profile: profile, override: overrides.first),
                    selectedDate: $selectedDate,
                    onLog: onLog
                )
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One day's content. Split out so the meal query can filter by `dayKey`.
private struct DayContent: View {
    let dayKey: String
    let date: Date
    let targets: DailyTargets
    @Binding var selectedDate: Date
    let onLog: (LogRequest) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var meals: [Meal]
    @AppStorage("lastCelebratedDay") private var lastCelebratedDay = ""
    @State private var undo: DeletedMeal?
    @State private var celebrate = false

    private let format = AppFormat.current
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    init(dayKey: String, date: Date, targets: DailyTargets, selectedDate: Binding<Date>, onLog: @escaping (LogRequest) -> Void) {
        self.dayKey = dayKey
        self.date = date
        self.targets = targets
        _selectedDate = selectedDate
        self.onLog = onLog
        _meals = Query(
            filter: #Predicate<Meal> { $0.dayKey == dayKey },
            sort: [SortDescriptor(\Meal.sortIndex), SortDescriptor(\Meal.loggedAt)]
        )
    }

    private var eaten: Macros { meals.reduce(.zero) { $0 + $1.totals } }

    private var relogKey: LocalizedStringKey {
        isToday ? LocalizedStringKey("meal.relog") : LocalizedStringKey("meal.logAgainToday")
    }

    var body: some View {
        List {
            Section {
                TodayHeader(date: date, isToday: isToday)
                DateStrip(selectedDate: $selectedDate)
                CalorieRing(eaten: eaten.kcal, target: targets.calories, format: format)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.xs)
                macroCard
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Theme.Space.xs, leading: Theme.Space.screenMargin,
                                      bottom: Theme.Space.xs, trailing: Theme.Space.screenMargin))

            ForEach(MealType.allCases) { type in
                mealSection(type)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.bg)
        .overlay(alignment: .bottom) { undoToast }
        .overlay { if celebrate { CelebrationView(reduceMotion: reduceMotion).allowsHitTesting(false) } }
        .onChange(of: eaten.kcal) { old, new in
            checkCelebration(old: old, new: new)
        }
    }

    private var macroCard: some View {
        VStack(spacing: Theme.Space.sm) {
            MacroBar(kind: .protein, eaten: eaten.protein, target: targets.proteinG, format: format)
            MacroBar(kind: .carbs, eaten: eaten.carbs, target: targets.carbsG, format: format)
            MacroBar(kind: .fat, eaten: eaten.fat, target: targets.fatG, format: format)
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(color: Theme.Palette.ink.opacity(0.06), radius: 8, y: 3)
    }

    // MARK: Meal groups

    @ViewBuilder
    private func mealSection(_ type: MealType) -> some View {
        let group = meals.filter { $0.mealType == type }
        Section {
            if group.isEmpty {
                Button {
                    onLog(LogRequest(date: logDate, mealType: type))
                } label: {
                    Text(type.addKey)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .strokeBorder(Theme.Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                }
                .buttonStyle(.plain)
                .dropDestination(for: String.self) { ids, _ in move(ids, to: type) }
            } else {
                ForEach(group) { meal in
                    MealCard(meal: meal, format: format)
                        .draggable(meal.id.uuidString)
                        .dropDestination(for: String.self) { ids, _ in move(ids, to: type) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { delete(meal) } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { logAgainToday(meal) } label: {
                                Label(relogKey, systemImage: "arrow.clockwise")
                            }
                            .tint(Theme.Palette.primary)
                        }
                        .contextMenu { mealMenu(meal) }
                }
            }
        } header: {
            HStack {
                Text(type.titleKey)
                Spacer()
                Text(verbatim: "\(format.number(Int(group.reduce(0) { $0 + $1.totals.kcal }.rounded()))) \(String(localized: "unit.kcal"))")
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.muted)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Palette.ink)
            .textCase(nil)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: Theme.Space.xxs, leading: Theme.Space.screenMargin,
                                  bottom: Theme.Space.xxs, trailing: Theme.Space.screenMargin))
    }

    @ViewBuilder
    private func mealMenu(_ meal: Meal) -> some View {
        Menu {
            ForEach(MealType.allCases) { type in
                Button {
                    meal.mealType = type
                    save()
                } label: {
                    Text(type.titleKey)
                }
                .disabled(meal.mealType == type)
            }
        } label: {
            Label("meal.changeType", systemImage: "arrow.left.arrow.right")
        }
        Button { logAgainToday(meal) } label: {
            Label(relogKey, systemImage: "arrow.clockwise")
        }
        Button(role: .destructive) { delete(meal) } label: {
            Label("common.delete", systemImage: "trash")
        }
    }

    // MARK: Actions

    /// Logging from a past day goes into that day at the current time of day.
    private var logDate: Date {
        guard !isToday else { return .now }
        let time = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return Calendar.current.date(byAdding: time, to: date) ?? date
    }

    private func move(_ ids: [String], to type: MealType) -> Bool {
        let moved = meals.filter { ids.contains($0.id.uuidString) }
        guard !moved.isEmpty else { return false }
        for meal in moved { meal.mealType = type }
        save()
        return true
    }

    private func logAgainToday(_ meal: Meal) {
        let copy = Meal(mealType: meal.mealType, source: meal.source, title: meal.title)
        context.insert(copy)
        copy.append(meal.orderedItems.map { $0.copy() })
        save()
    }

    private func delete(_ meal: Meal) {
        undo = DeletedMeal(meal)
        context.delete(meal)
        save()
        let token = undo?.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if undo?.id == token { undo = nil }
        }
    }

    private func save() {
        try? context.save()
    }

    private func checkCelebration(old: Double, new: Double) {
        let target = Double(targets.calories)
        guard isToday, target > 0, old < target, new >= target, lastCelebratedDay != dayKey else { return }
        lastCelebratedDay = dayKey
        celebrate = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            celebrate = false
        }
    }

    @ViewBuilder
    private var undoToast: some View {
        if let deleted = undo {
            HStack(spacing: Theme.Space.md) {
                Text("meal.deleted").font(.callout)
                Spacer()
                Button("common.undo") {
                    deleted.restore(into: context)
                    save()
                    undo = nil
                }
                .font(.callout.weight(.semibold))
                .tint(Theme.Palette.halo)
            }
            .foregroundStyle(Theme.Palette.bg)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.Palette.ink, in: Capsule())
            .padding(Theme.Space.screenMargin)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Enough of a deleted meal to put it back (Undo).
private struct DeletedMeal {
    struct Item {
        let nameAr, nameEn: String
        let grams: Double
        let per100: Macros
        let valueSource: String
        let foodDbId, barcode: String?
        let confidence: Double?
    }

    let id = UUID()
    let mealID: UUID
    let loggedAt: Date
    let mealType: MealType
    let source: LogSource
    let sortIndex: Int
    let title: String?
    let items: [Item]

    init(_ meal: Meal) {
        mealID = meal.id
        loggedAt = meal.loggedAt
        mealType = meal.mealType
        source = meal.source
        sortIndex = meal.sortIndex
        title = meal.title
        items = meal.orderedItems.map {
            Item(nameAr: $0.nameAr, nameEn: $0.nameEn, grams: $0.grams, per100: $0.per100,
                 valueSource: $0.valueSourceRaw, foodDbId: $0.foodDbId, barcode: $0.barcode, confidence: $0.confidence)
        }
    }

    func restore(into context: ModelContext) {
        let meal = Meal(id: mealID, loggedAt: loggedAt, mealType: mealType, source: source,
                        sortIndex: sortIndex, title: title)
        context.insert(meal)
        meal.append(items.map {
            MealItem(nameAr: $0.nameAr, nameEn: $0.nameEn, grams: $0.grams, per100: $0.per100,
                     valueSource: ValueSource(rawValue: $0.valueSource) ?? .user,
                     foodDbId: $0.foodDbId, barcode: $0.barcode, confidence: $0.confidence)
        })
    }
}

extension MealType {
    var titleKey: LocalizedStringKey {
        switch self {
        case .breakfast: "meal.breakfast"
        case .lunch: "meal.lunch"
        case .dinner: "meal.dinner"
        case .snack: "meal.snack"
        }
    }

    var addKey: LocalizedStringKey {
        switch self {
        case .breakfast: "meal.add.breakfast"
        case .lunch: "meal.add.lunch"
        case .dinner: "meal.add.dinner"
        case .snack: "meal.add.snack"
        }
    }
}

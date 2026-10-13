import LakhasKit
import SwiftData
import SwiftUI

/// The center "+" sheet (docs/design.md §4): Photo · Text · Barcode · Saved meal.
/// The AI methods arrive in Phases 4–5; Phase 3 adds a manual quick add on local data.
struct LogSheet: View {
    let request: LogRequest
    @Environment(\.dismiss) private var dismiss
    @State private var hasKey = AIKeyStore().hasKey(for: AISettings.load().provider)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    aiMethod("log.photo", symbol: "camera", identifier: "ax.log.photo")
                    aiMethod("log.text", symbol: "text.bubble", identifier: "ax.log.text")
                    method("log.barcode", symbol: "barcode.viewfinder", phaseKey: "log.comingSoon")
                    method("log.saved", symbol: "bookmark", phaseKey: "log.comingSoon")
                } footer: {
                    if !hasKey { Text("log.needsKey") }
                }
                Section {
                    NavigationLink {
                        QuickAddView(request: request) { dismiss() }
                    } label: {
                        Label("log.quickAdd", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("ax.log.quickAdd")
                } footer: {
                    Text("log.quickAdd.footer")
                }
            }
            .navigationTitle("log.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .onAppear { hasKey = AIKeyStore().hasKey(for: AISettings.load().provider) }
        }
        .presentationDetents([.medium, .large])
        .tint(Theme.Palette.primary)
    }

    /// Photo / text analysis need the user's own key (ADR-020).
    private func aiMethod(_ key: LocalizedStringKey, symbol: String, identifier: String) -> some View {
        NavigationLink {
            if hasKey { AIComingSoonView() } else { NoKeyView() }
        } label: {
            HStack {
                Label(key, systemImage: symbol)
                Spacer()
                if !hasKey {
                    Image(systemName: "key.horizontal").font(.caption).foregroundStyle(Theme.Palette.muted)
                }
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func method(_ key: LocalizedStringKey, symbol: String, phaseKey: LocalizedStringKey) -> some View {
        HStack {
            Label(key, systemImage: symbol)
            Spacer()
            Text(phaseKey).font(.caption).foregroundStyle(Theme.Palette.muted)
        }
        .foregroundStyle(Theme.Palette.muted)
        .accessibilityElement(children: .combine)
    }
}

/// Manual entry of a meal's totals. Stored as one item of 100 g whose per-100 g values are
/// the entered totals, so totals still come from grams × per-100 g.
struct QuickAddView: View {
    let request: LogRequest
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var mealType: MealType
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var saved = 0

    private let format = AppFormat.current

    init(request: LogRequest, onDone: @escaping () -> Void) {
        self.request = request
        self.onDone = onDone
        _mealType = State(initialValue: request.mealType ?? MealType.suggested(for: request.date))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kcal ?? 0) > 0
    }

    var body: some View {
        Form {
            Section {
                TextField("quickadd.name", text: $name)
                    .accessibilityIdentifier("ax.quickadd.name")
                Picker("quickadd.mealType", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.titleKey).tag($0) }
                }
            }
            Section {
                numberField("quickadd.kcal", value: $kcal, unitKey: "unit.kcal", identifier: "ax.quickadd.kcal")
                numberField("macro.protein", value: $protein, unitKey: "unit.g", identifier: "ax.quickadd.protein")
                numberField("macro.carbs", value: $carbs, unitKey: "unit.g", identifier: "ax.quickadd.carbs")
                numberField("macro.fat", value: $fat, unitKey: "unit.g", identifier: "ax.quickadd.fat")
            } footer: {
                Text("quickadd.footer")
            }
        }
        .navigationTitle("log.quickAdd")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save", action: save)
                    .disabled(!canSave)
                    .accessibilityIdentifier("ax.quickadd.save")
            }
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    private func numberField(_ key: LocalizedStringKey, value: Binding<Double?>, unitKey: LocalizedStringKey,
                             identifier: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            TextField(key, value: value, format: .number.locale(format.locale))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .accessibilityIdentifier(identifier)
            Text(unitKey).foregroundStyle(Theme.Palette.muted)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let meal = Meal(loggedAt: request.date, mealType: mealType, source: .manual, title: trimmed)
        context.insert(meal)
        meal.append([MealItem(
            nameAr: trimmed, nameEn: trimmed, grams: 100,
            per100: Macros(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0),
            valueSource: .user
        )])
        try? context.save()
        saved += 1
        onDone()
    }
}

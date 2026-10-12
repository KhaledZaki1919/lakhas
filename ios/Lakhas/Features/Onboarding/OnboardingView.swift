import LakhasKit
import SwiftData
import SwiftUI

/// Onboarding (PROJECT_PROMPT.md §4.1): collects the body profile, shows a plain-language
/// summary with BMI category, healthy range and computed targets, then saves the profile.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, sex, age, height, weight, activity, goal, summary
    }

    @Environment(\.modelContext) private var context
    @State private var step: Step = .welcome
    @State private var sex: Sex?
    @State private var age = 30
    @State private var heightCm = 170
    @State private var weightKg = 70.0
    @State private var activity: ActivityLevel?
    @State private var goal: Goal?
    @State private var pace = 0.5

    private let format = AppFormat.current

    var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()
            VStack(spacing: Theme.Space.lg) {
                if step != .welcome {
                    progressHeader
                }
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Space.sm)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
            .padding(Theme.Space.screenMargin)
            .animation(.snappy, value: step)
        }
    }

    // MARK: Layout

    private var progressHeader: some View {
        HStack(spacing: Theme.Space.sm) {
            Button {
                if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .tint(Theme.Palette.ink)
            .accessibilityLabel(Text("common.back"))
            .accessibilityIdentifier("ax.onboarding.back")

            ProgressView(value: Double(step.rawValue), total: Double(Step.summary.rawValue))
                .tint(Theme.Palette.primary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .sex: sexStep
        case .age: wheelStep(titleKey: "onboarding.age.title", value: $age, range: Array(14...90), unitKey: "unit.years")
        case .height: wheelStep(titleKey: "onboarding.height.title", value: $heightCm, range: Array(120...220), unitKey: "unit.cm")
        case .weight: weightStep
        case .activity: activityStep
        case .goal: goalStep
        case .summary: summaryStep
        }
    }

    private var footer: some View {
        PrimaryButton(titleKey: footerKey, isEnabled: canContinue) {
            if step == .summary {
                finish()
            } else if let next = Step(rawValue: step.rawValue + 1) {
                step = next
            }
        }
        .accessibilityIdentifier(step == .summary ? "ax.onboarding.finish" : "ax.onboarding.next")
    }

    private var footerKey: LocalizedStringKey {
        switch step {
        case .welcome: "onboarding.start"
        case .summary: "onboarding.finish"
        default: "common.continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .sex: sex != nil
        case .activity: activity != nil
        case .goal: goal != nil
        default: true
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("common.appName")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Theme.Palette.primary)
                .padding(.top, Theme.Space.xxl)
            Text("onboarding.welcome.title")
                .font(.title.bold())
                .foregroundStyle(Theme.Palette.ink)
            Text("onboarding.welcome.body")
                .font(.body)
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    private func title(_ key: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(key).font(.title2.bold()).foregroundStyle(Theme.Palette.ink)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(Theme.Palette.muted)
            }
        }
        .padding(.bottom, Theme.Space.sm)
    }

    private var sexStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            title("onboarding.sex.title", subtitle: "onboarding.sex.subtitle")
            OptionCard(titleKey: "sex.male", symbol: "figure.stand", isSelected: sex == .male) { sex = .male }
                .accessibilityIdentifier("ax.onboarding.option.male")
            OptionCard(titleKey: "sex.female", symbol: "figure.stand.dress", isSelected: sex == .female) { sex = .female }
                .accessibilityIdentifier("ax.onboarding.option.female")
        }
    }

    private func wheelStep(titleKey: LocalizedStringKey, value: Binding<Int>, range: [Int], unitKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            title(titleKey)
            HStack {
                Picker(selection: value) {
                    ForEach(range, id: \.self) { number in
                        Text(verbatim: format.number(number)).tag(number)
                    }
                } label: {
                    Text(titleKey)
                }
                .pickerStyle(.wheel)
                Text(unitKey).font(.title3).foregroundStyle(Theme.Palette.muted)
            }
        }
    }

    private var weightStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            title("onboarding.weight.title")
            HStack {
                Picker(selection: $weightKg) {
                    ForEach(Array(stride(from: 35.0, through: 250.0, by: 0.5)), id: \.self) { kg in
                        Text(verbatim: format.number(kg, fractionDigits: 1)).tag(kg)
                    }
                } label: {
                    Text("onboarding.weight.title")
                }
                .pickerStyle(.wheel)
                Text("unit.kg").font(.title3).foregroundStyle(Theme.Palette.muted)
            }
        }
    }

    private var activityStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            title("onboarding.activity.title")
            ForEach(ActivityLevel.allCases, id: \.self) { level in
                OptionCard(titleKey: level.titleKey, subtitleKey: level.subtitleKey, symbol: level.symbol,
                           isSelected: activity == level) { activity = level }
                    .accessibilityIdentifier("ax.onboarding.option.\(level.rawValue)")
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            title("onboarding.goal.title")
            ForEach(Goal.allCases, id: \.self) { option in
                OptionCard(titleKey: option.titleKey, symbol: option.symbol, isSelected: goal == option) {
                    goal = option
                    if !option.paces.contains(pace) { pace = option.paces.first ?? 0 }
                }
                .accessibilityIdentifier("ax.onboarding.option.\(option.rawValue)")
            }
            if let goal, goal != .maintain {
                Text("onboarding.pace.title")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.top, Theme.Space.sm)
                Picker(selection: $pace) {
                    ForEach(goal.paces, id: \.self) { value in
                        Text(verbatim: String(localized: "onboarding.pace.value \(format.number(value, fractionDigits: 2))")).tag(value)
                    }
                } label: {
                    Text("onboarding.pace.title")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var summaryStep: some View {
        let profile = draftProfile
        let summary = NutritionMath.bodySummary(weightKg: profile.weightKg, heightCm: profile.heightCm)
        let targets = NutritionMath.targets(for: profile)
        return VStack(alignment: .leading, spacing: Theme.Space.md) {
            title("onboarding.summary.title")

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(verbatim: String(localized: "onboarding.summary.bmi \(format.number(summary.bmi, fractionDigits: 1))"))
                    .font(.headline)
                Text(summary.category.descriptionKey)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.muted)
                Text(verbatim: String(localized: "onboarding.summary.range \(format.number(summary.healthyMinKg.rounded())) \(format.number(summary.healthyMaxKg.rounded()))"))
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.muted)
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("onboarding.summary.targets").font(.headline)
                Text(verbatim: "\(format.number(targets.calories)) \(String(localized: "unit.kcal"))")
                    .font(.largeTitle.bold().monospacedDigit())
                    .foregroundStyle(Theme.Palette.primary)
                    .accessibilityIdentifier("ax.onboarding.summary.calories")
                HStack {
                    summaryChip(.protein, grams: targets.proteinG)
                    summaryChip(.carbs, grams: targets.carbsG)
                    summaryChip(.fat, grams: targets.fatG)
                }
                Label {
                    Text(verbatim: String(localized: "onboarding.summary.water \(format.number(targets.waterMl))"))
                } icon: {
                    Image(systemName: "drop.fill").foregroundStyle(Theme.Palette.protein)
                }
                .font(.callout)
                if targets.floorApplied {
                    Text("onboarding.summary.floorNote")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))

            Text("onboarding.summary.disclaimer")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    private func summaryChip(_ kind: MacroKind, grams: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(kind.nameKey).font(.caption.weight(.medium))
            } icon: {
                Image(systemName: kind.symbol).foregroundStyle(kind.color)
            }
            Text(verbatim: "\(format.number(grams)) \(String(localized: "unit.g"))")
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Model

    private var draftProfile: BodyProfile {
        BodyProfile(sex: sex ?? .male, age: age, heightCm: Double(heightCm), weightKg: weightKg,
                    activity: activity ?? .sedentary, goal: goal ?? .maintain,
                    paceKgPerWeek: goal == .maintain ? 0 : pace)
    }

    private func finish() {
        let draft = draftProfile
        let year = Calendar.current.component(.year, from: .now)
        context.insert(UserProfile(sex: draft.sex, birthYear: year - draft.age, heightCm: draft.heightCm,
                                   weightKg: draft.weightKg, activity: draft.activity, goal: draft.goal,
                                   paceKgPerWeek: draft.paceKgPerWeek))
        try? context.save()
    }
}

extension ActivityLevel {
    var titleKey: LocalizedStringKey {
        switch self {
        case .sedentary: "activity.sedentary"
        case .light: "activity.light"
        case .active: "activity.active"
        case .veryActive: "activity.veryActive"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .sedentary: "activity.sedentary.detail"
        case .light: "activity.light.detail"
        case .active: "activity.active.detail"
        case .veryActive: "activity.veryActive.detail"
        }
    }

    var symbol: String {
        switch self {
        case .sedentary: "chair.lounge"
        case .light: "figure.walk"
        case .active: "figure.run"
        case .veryActive: "figure.strengthtraining.traditional"
        }
    }
}

extension Goal {
    var titleKey: LocalizedStringKey {
        switch self {
        case .lose: "goal.lose"
        case .maintain: "goal.maintain"
        case .gain: "goal.gain"
        }
    }

    var symbol: String {
        switch self {
        case .lose: "arrow.down.right"
        case .maintain: "equal"
        case .gain: "arrow.up.right"
        }
    }
}

extension BMICategory {
    var descriptionKey: LocalizedStringKey {
        switch self {
        case .underweight: "bmi.underweight"
        case .normal: "bmi.normal"
        case .overweight: "bmi.overweight"
        case .obese: "bmi.obese"
        }
    }
}

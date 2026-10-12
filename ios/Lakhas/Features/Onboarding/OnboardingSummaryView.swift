import LakhasKit
import SwiftUI

/// Last onboarding step: BMI in plain words, healthy range, targets and the floor note.
struct OnboardingSummaryView: View {
    let profile: BodyProfile
    let format: AppFormat

    var body: some View {
        let summary = NutritionMath.bodySummary(weightKg: profile.weightKg, heightCm: profile.heightCm)
        let targets = NutritionMath.targets(for: profile)
        return VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("onboarding.summary.title").font(.title2.bold()).foregroundStyle(Theme.Palette.ink)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(verbatim: String(localized: "onboarding.summary.bmi \(format.number(summary.bmi, fractionDigits: 1))"))
                    .font(.headline)
                Text(summary.category.descriptionKey)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.muted)
                Text(verbatim: healthyRange(summary))
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

    private func healthyRange(_ summary: BodySummary) -> String {
        let low = format.number(summary.healthyMinKg.rounded())
        let high = format.number(summary.healthyMaxKg.rounded())
        return String(localized: "onboarding.summary.range \(low) \(high)")
    }
}

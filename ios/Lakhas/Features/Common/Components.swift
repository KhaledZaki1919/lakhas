import LakhasKit
import SwiftUI

/// Large selectable card used in onboarding (sex, activity, goal).
struct OptionCard: View {
    let titleKey: LocalizedStringKey
    var subtitleKey: LocalizedStringKey?
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(isSelected ? Theme.Palette.onPrimary : Theme.Palette.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey).font(.headline)
                    if let subtitleKey {
                        Text(subtitleKey)
                            .font(.footnote)
                            .foregroundStyle(isSelected ? Theme.Palette.onPrimary.opacity(0.85) : Theme.Palette.muted)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.title3)
                }
            }
            .foregroundStyle(isSelected ? Theme.Palette.onPrimary : Theme.Palette.ink)
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.Palette.primary : Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .shadow(color: Theme.Palette.ink.opacity(isSelected ? 0 : 0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Full-width primary capsule button (docs/design.md §3).
struct PrimaryButton: View {
    let titleKey: LocalizedStringKey
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Theme.Palette.primary)
        .disabled(!isEnabled)
    }
}

/// Labeled macro row: glyph + name + "eaten / target g" + bar (never color alone).
struct MacroBar: View {
    let kind: MacroKind
    let eaten: Double
    let target: Int
    let format: AppFormat

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            HStack {
                Label {
                    Text(kind.nameKey).font(.footnote.weight(.semibold))
                } icon: {
                    Image(systemName: kind.symbol).foregroundStyle(kind.color)
                }
                Spacer()
                Text(verbatim: "\(format.number(Int(eaten.rounded()))) / \(format.number(target)) \(String(localized: "unit.g"))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.Palette.muted)
            }
            ProgressView(value: min(eaten, Double(max(target, 1))), total: Double(max(target, 1)))
                .tint(kind.color)
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.nameKey))
        .accessibilityValue(Text(verbatim: String(localized: "macro.a11y \(format.number(Int(eaten.rounded()))) \(format.number(target))")))
    }
}

enum MacroKind: CaseIterable {
    case protein, carbs, fat

    var nameKey: LocalizedStringKey {
        switch self {
        case .protein: "macro.protein"
        case .carbs: "macro.carbs"
        case .fat: "macro.fat"
        }
    }

    var symbol: String {
        switch self {
        case .protein: "oval.fill"
        case .carbs: "leaf.fill"
        case .fat: "drop.fill"
        }
    }

    var color: Color {
        switch self {
        case .protein: Theme.Palette.protein
        case .carbs: Theme.Palette.carbs
        case .fat: Theme.Palette.fat
        }
    }
}

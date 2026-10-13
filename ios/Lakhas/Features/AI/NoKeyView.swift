import LakhasKit
import SwiftUI

/// Shown by every AI entry point when no key is set for the chosen provider (ADR-020).
/// There is no fallback: the user brings their own key or uses the non-AI features.
struct NoKeyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Palette.primary)
                    .accessibilityHidden(true)
                Text("nokey.title")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("ax.nokey.title")
                Text("nokey.body")
                    .font(.body)
                    .foregroundStyle(Theme.Palette.muted)

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    step(1, "nokey.step1")
                    step(2, "nokey.step2")
                    step(3, "nokey.step3")
                }

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(AIProviderKind.allCases) { kind in
                        if let url = kind.keyPageURL {
                            Link(destination: url) {
                                Label {
                                    Text(verbatim: kind.displayName)
                                } icon: {
                                    Image(systemName: "arrow.up.right.square")
                                }
                            }
                            .font(.callout.weight(.semibold))
                            .tint(Theme.Palette.primary)
                        }
                    }
                }

                Text("nokey.cost")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.muted)

                NavigationLink {
                    AISettingsView()
                } label: {
                    Text("nokey.open")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.Palette.primary)
                .accessibilityIdentifier("ax.nokey.open")

                Text("nokey.withoutKey")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.muted)
            }
            .padding(Theme.Space.screenMargin)
        }
        .background(Theme.Palette.bg)
    }

    private func step(_ number: Int, _ key: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text(verbatim: AppFormat.current.number(number))
                .font(.callout.bold())
                .foregroundStyle(Theme.Palette.onPrimary)
                .frame(width: 26, height: 26)
                .background(Theme.Palette.primary, in: Circle())
            Text(key).font(.callout).foregroundStyle(Theme.Palette.ink)
        }
    }
}

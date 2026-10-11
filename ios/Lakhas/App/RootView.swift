import LakhasKit
import SwiftUI

/// Phase 1 shell. The custom tab bar with the centered "+" (docs/design.md §4) arrives in Phase 3.
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { TodayPlaceholderView() }
                .tabItem { Label("tab.today", systemImage: "circle.circle") }
            NavigationStack { PlaceholderView(titleKey: "tab.recipes") }
                .tabItem { Label("tab.recipes", systemImage: "book") }
            NavigationStack { PlaceholderView(titleKey: "tab.explore") }
                .tabItem { Label("tab.explore", systemImage: "safari") }
            NavigationStack { PlaceholderView(titleKey: "tab.workouts") }
                .tabItem { Label("tab.workouts", systemImage: "dumbbell") }
        }
        .tint(Theme.Palette.primary)
    }
}

struct TodayPlaceholderView: View {
    var body: some View {
        PlaceholderView(titleKey: "tab.today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CapabilityProbeView()
                    } label: {
                        Label("probe.title", systemImage: "stethoscope")
                    }
                }
            }
    }
}

struct PlaceholderView: View {
    let titleKey: LocalizedStringKey

    var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()
            VStack(spacing: Theme.Space.sm) {
                Text("common.appName")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.Palette.primary)
                Text("common.comingSoon")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.muted)
            }
            .padding(Theme.Space.screenMargin)
        }
        .navigationTitle(titleKey)
    }
}

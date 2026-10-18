import LakhasKit
import SwiftUI

/// Placeholder for tabs built in later phases (Explore 8, Workouts 9, Progress 10).
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

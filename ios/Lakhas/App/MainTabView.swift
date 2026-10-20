import LakhasKit
import SwiftUI

enum AppTab: Hashable {
    case today, recipes, explore, workouts
}

/// Tab bar per ADR-017 / docs/design.md §4: Today, Recipes, [+], Explore, Workouts.
/// Progress lives in the Today header, so the "+" is truly centered (2 + 2).
struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today
    @State private var logRequest: LogRequest?
    @State private var recipeImport: RecipeImportRequest?
    @State private var offer: ImportOffer?

    private let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView(onLog: { logRequest = $0 }) }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.today)
            NavigationStack { RecipesHubView { recipeImport = RecipeImportRequest() } }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.recipes)
            NavigationStack { ExploreView() }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.explore)
            NavigationStack { PlaceholderView(titleKey: "tab.workouts") }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.workouts)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LakhasTabBar(selection: $tab) {
                logRequest = LogRequest(date: .now, mealType: nil)
            }
            // Stays at the bottom behind the keyboard instead of riding up over forms.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .sheet(item: $logRequest) { request in
            LogSheet(request: request)
        }
        .sheet(item: $recipeImport) { request in
            RecipeImportView(request: request)
        }
        .alert("recipes.offer.title", isPresented: Binding(get: { offer != nil }, set: { if !$0 { offer = nil } }),
               presenting: offer) { offer in
            Button("recipes.offer.import") { accept(offer) }
            Button("recipes.offer.notNow", role: .cancel) { decline(offer) }
        } message: { offer in
            Text(offer.messageKey)
        }
        .task { await lookForSharedLink() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await lookForSharedLink() } }
        }
    }

    // MARK: Shared links (share extension hand-off)

    private func lookForSharedLink() async {
        guard !uiTesting, offer == nil, recipeImport == nil, logRequest == nil else { return }
        offer = await ImportOfferFinder.next()
    }

    private func accept(_ offer: ImportOffer) {
        let link: String?
        switch offer {
        case .queued(let item):
            ImportOfferFinder.remove(item)
            link = item.url.absoluteString
        case .clipboard:
            link = ImportOfferFinder.clipboardText()
        }
        // The extension copies the link as well; it has been handled now.
        ImportOfferFinder.markClipboardSeen()
        tab = .recipes
        recipeImport = RecipeImportRequest(link: link)
    }

    private func decline(_ offer: ImportOffer) {
        if case .queued(let item) = offer { ImportOfferFinder.remove(item) }
        ImportOfferFinder.markClipboardSeen()
    }
}

/// What the log sheet should prefill: the day being viewed and, from an empty group, its meal type.
struct LogRequest: Identifiable {
    let id = UUID()
    let date: Date
    let mealType: MealType?
}

struct LakhasTabBar: View {
    @Binding var selection: AppTab
    let onPlus: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            item(.today, key: "tab.today", symbol: "circle.circle")
            item(.recipes, key: "tab.recipes", symbol: "book")
            plusButton
            item(.explore, key: "tab.explore", symbol: "safari")
            item(.workouts, key: "tab.workouts", symbol: "dumbbell")
        }
        .padding(.top, Theme.Space.xs)
        .padding(.horizontal, Theme.Space.xxs)
        .background {
            Theme.Palette.surface
                .overlay(alignment: .top) { Theme.Palette.line.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: AppTab, key: LocalizedStringKey, symbol: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(key)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.Palette.primary : Theme.Palette.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("ax.tab.\(String(describing: tab))")
    }

    private var plusButton: some View {
        Button(action: onPlus) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.Palette.onPrimary)
                .frame(width: 54, height: 54)
                .background(Theme.Palette.primary, in: Circle())
                .overlay(Circle().stroke(Theme.Palette.halo, lineWidth: 5))
        }
        .buttonStyle(.plain)
        .offset(y: -22)
        .frame(width: 76)
        .accessibilityLabel(Text("log.title"))
        .accessibilityIdentifier("ax.tab.plus")
    }
}

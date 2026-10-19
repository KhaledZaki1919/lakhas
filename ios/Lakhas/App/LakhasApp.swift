import LakhasKit
import SwiftData
import SwiftUI

@main
struct LakhasApp: App {
    private let container: ModelContainer?
    @State private var account: AccountModel

    init() {
        // UI tests launch with -uiTesting: in-memory store and default AI settings (no key).
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if uiTesting {
            UserDefaults.standard.removeObject(forKey: AISettings.defaultsKey)
            AIDiagnosticsStore.clear()
            // Barcode lookups are answered from a fixed table, never the network.
            OpenFoodFactsClient.uiTestingProducts = UITestingAIProvider.products
            // Recipe pages likewise: one known link, everything else reads like a login wall.
            RecipePageFetcher.uiTestingPages = UITestingAIProvider.recipePages
            // Our server likewise: an in-memory stand-in, secrets in memory (ADR-027).
            ServerConfig.uiTestingProtocol = UITestingServer.self
            UITestingServer.reset()
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestingStubAI") {
            AIService.overrideProvider = UITestingAIProvider()
        }
        container = try? LakhasStore.makeContainer(inMemory: uiTesting)
        _account = State(initialValue: AccountModel(uiTesting: uiTesting))
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootGate()
                    .modelContainer(container)
                    .environment(account)
            } else {
                StoreErrorView()
            }
        }
    }
}

/// Onboarding until a profile exists, then the app. The account is optional (ADR-027).
struct RootGate: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if profiles.isEmpty {
            OnboardingView()
        } else {
            MainTabView()
        }
    }
}

struct StoreErrorView: View {
    var body: some View {
        ContentUnavailableView {
            Label("common.storeError.title", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("common.storeError.body")
        }
    }
}

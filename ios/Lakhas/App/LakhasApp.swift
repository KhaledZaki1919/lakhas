import LakhasKit
import SwiftData
import SwiftUI

@main
struct LakhasApp: App {
    private let container: ModelContainer?

    init() {
        // UI tests launch with -uiTesting: in-memory store and default AI settings (no key).
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if uiTesting {
            UserDefaults.standard.removeObject(forKey: AISettings.defaultsKey)
            AIDiagnosticsStore.clear()
            // Barcode lookups are answered from a fixed table, never the network.
            OpenFoodFactsClient.uiTestingProducts = UITestingAIProvider.products
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestingStubAI") {
            AIService.overrideProvider = UITestingAIProvider()
        }
        container = try? LakhasStore.makeContainer(inMemory: uiTesting)
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootGate().modelContainer(container)
            } else {
                StoreErrorView()
            }
        }
    }
}

/// Onboarding until a profile exists, then the app. No accounts, no tokens (ADR-020).
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

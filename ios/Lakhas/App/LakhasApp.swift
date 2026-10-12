import LakhasKit
import SwiftData
import SwiftUI

@main
struct LakhasApp: App {
    @State private var model: AppModel
    private let container: ModelContainer?

    init() {
        // UI tests launch with -uiTesting: in-memory store, no token, no server.
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        let model = uiTesting
            ? AppModel(tokenStore: TokenStore(keychain: KeychainStore(service: "lakhas.uitest")))
            : AppModel()
        if uiTesting {
            model.forgetToken()
            model.continueOffline()
        }
        _model = State(initialValue: model)
        container = try? LakhasStore.makeContainer(inMemory: uiTesting)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootGate().modelContainer(container)
                } else {
                    StoreErrorView()
                }
            }
            .environment(model)
        }
    }
}

/// Token first (ADR-013), then onboarding until a profile exists, then the app.
struct RootGate: View {
    @Environment(AppModel.self) private var model
    @Query private var profiles: [UserProfile]

    var body: some View {
        switch model.phase {
        case .needsToken:
            TokenEntryView()
        case .ready, .offline:
            if profiles.isEmpty {
                OnboardingView()
            } else {
                MainTabView()
            }
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

import SwiftUI

@main
struct LakhasApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch model.phase {
                case .needsToken:
                    TokenEntryView()
                case .ready, .offline:
                    RootView()
                }
            }
            .environment(model)
        }
    }
}

import SwiftUI
import WrapAround

// The iOS host: only the entry point. The whole app is WrapAroundRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            WrapAroundRootView()
        }
    }
}

import SwiftUI
import Skies

// The iOS host: only the entry point. The whole app is SkiesRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            SkiesRootView()
        }
    }
}

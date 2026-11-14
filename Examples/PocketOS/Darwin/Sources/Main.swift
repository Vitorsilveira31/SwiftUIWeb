import SwiftUI
import PocketOS

// The iOS host: only the entry point. The whole app is PocketOSRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            PocketOSRootView()
        }
    }
}

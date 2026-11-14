import SwiftUI
import SwipeDeck

// The iOS host: only the entry point. The whole app is SwipeDeckRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            SwipeDeckRootView()
        }
    }
}

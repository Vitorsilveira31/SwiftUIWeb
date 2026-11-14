import SwiftUI
import StoreMap

// The iOS host: only the entry point. The whole app is StoreMapRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            StoreMapRootView()
        }
    }
}

import SwiftUI
import ClipPlayer

// The iOS host: only the entry point. The whole app is ClipPlayerRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            ClipPlayerRootView()
        }
    }
}

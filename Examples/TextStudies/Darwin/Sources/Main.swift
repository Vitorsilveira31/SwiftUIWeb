import SwiftUI
import TextStudies

// The iOS host: only the entry point. The whole app is TextStudiesRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            TextStudiesRootView()
        }
    }
}

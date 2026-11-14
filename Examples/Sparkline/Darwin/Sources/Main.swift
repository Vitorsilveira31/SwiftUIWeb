import SwiftUI
import Sparkline

// The iOS host: only the entry point. The whole app is SparklineRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            SparklineRootView()
        }
    }
}

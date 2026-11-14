import SwiftUI
import MarkdownReader

// The iOS host: only the entry point. The whole app is MarkdownReaderRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            MarkdownReaderRootView()
        }
    }
}

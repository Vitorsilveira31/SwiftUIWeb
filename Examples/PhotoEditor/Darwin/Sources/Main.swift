import SwiftUI
import PhotoEditor

// The iOS host: only the entry point. The whole app is PhotoEditorRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            PhotoEditorRootView()
        }
    }
}

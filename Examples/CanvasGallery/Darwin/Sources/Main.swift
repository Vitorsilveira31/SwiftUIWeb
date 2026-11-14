import SwiftUI
import CanvasGallery

// The iOS host: only the entry point. The whole app is CanvasGalleryRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            CanvasGalleryRootView()
        }
    }
}

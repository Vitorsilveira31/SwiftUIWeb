import SwiftUI
import ShapeGallery

// The iOS host: only the entry point. The whole app is ShapeGalleryRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            ShapeGalleryRootView()
        }
    }
}

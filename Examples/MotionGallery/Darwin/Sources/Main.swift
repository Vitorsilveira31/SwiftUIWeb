import SwiftUI
import MotionGallery

// The iOS host: only the entry point. The whole app is MotionGalleryRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            MotionGalleryRootView()
        }
    }
}

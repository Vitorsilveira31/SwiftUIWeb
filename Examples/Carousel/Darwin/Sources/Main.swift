import SwiftUI
import Carousel

// The iOS host: only the entry point. The whole app is CarouselRootView from the package.
@main struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            CarouselRootView()
        }
    }
}

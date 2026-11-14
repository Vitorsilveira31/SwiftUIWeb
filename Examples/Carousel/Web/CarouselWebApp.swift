import SwiftUIWeb
import SwiftUIWebBrowser
import Carousel

// The browser host: only the entry point. The whole app is CarouselRootView from Sources/Carousel.
@main
struct CarouselWebApp: BrowserApp {
    var body: some View { WindowGroup { CarouselRootView() } }
}

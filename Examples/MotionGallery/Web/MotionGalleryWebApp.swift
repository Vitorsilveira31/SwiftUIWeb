import SwiftUIWeb
import SwiftUIWebBrowser
import MotionGallery

// The browser host: only the entry point. The whole app is MotionGalleryRootView from Sources/MotionGallery.
@main
struct MotionGalleryWebApp: BrowserApp {
    var body: some View { WindowGroup { MotionGalleryRootView() } }
}

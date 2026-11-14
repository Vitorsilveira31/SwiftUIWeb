import SwiftUIWeb
import SwiftUIWebBrowser
import CanvasGallery

// The browser host: only the entry point. The whole app is CanvasGalleryRootView from Sources/CanvasGallery.
@main
struct CanvasGalleryWebApp: BrowserApp {
    var body: some View { WindowGroup { CanvasGalleryRootView() } }
}

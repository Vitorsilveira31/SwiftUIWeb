import SwiftUIWeb
import SwiftUIWebBrowser
import ShapeGallery

// The browser host: only the entry point. The whole app is ShapeGalleryRootView from Sources/ShapeGallery.
@main
struct ShapeGalleryWebApp: BrowserApp {
    var body: some View { WindowGroup { ShapeGalleryRootView() } }
}

import SwiftUIWeb
import SwiftUIWebBrowser
import StoreMap

// The browser host: only the entry point. The whole app is StoreMapRootView from Sources/StoreMap.
@main
struct StoreMapWebApp: BrowserApp {
    var body: some View { WindowGroup { StoreMapRootView() } }
}

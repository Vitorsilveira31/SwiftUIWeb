import SwiftUIWeb
import SwiftUIWebBrowser
import PocketOS

// The browser host: only the entry point. The whole app is PocketOSRootView from Sources/PocketOS.
@main
struct PocketOSWebApp: BrowserApp {
    var body: some View { WindowGroup { PocketOSRootView() } }
}

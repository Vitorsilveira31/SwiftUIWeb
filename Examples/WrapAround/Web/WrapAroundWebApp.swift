import SwiftUIWeb
import SwiftUIWebBrowser
import WrapAround

// The browser host: only the entry point. The whole app is WrapAroundRootView from Sources/WrapAround.
@main
struct WrapAroundWebApp: BrowserApp {
    var body: some View { WindowGroup { WrapAroundRootView() } }
}

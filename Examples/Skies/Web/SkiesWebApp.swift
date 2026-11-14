import SwiftUIWeb
import SwiftUIWebBrowser
import Skies

// The browser host: only the entry point. The whole app is SkiesRootView from Sources/Skies.
@main
struct SkiesWebApp: BrowserApp {
    var body: some View { WindowGroup { SkiesRootView() } }
}

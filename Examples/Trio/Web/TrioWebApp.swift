import SwiftUIWeb
import SwiftUIWebBrowser
import Trio

// The browser host: only the entry point. The whole app is TrioRootView from Sources/Trio.
@main
struct TrioWebApp: BrowserApp {
    var body: some View { WindowGroup { TrioRootView() } }
}

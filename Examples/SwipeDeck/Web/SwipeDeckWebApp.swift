import SwiftUIWeb
import SwiftUIWebBrowser
import SwipeDeck

// The browser host: only the entry point. The whole app is SwipeDeckRootView from Sources/SwipeDeck.
@main
struct SwipeDeckWebApp: BrowserApp {
    var body: some View { WindowGroup { SwipeDeckRootView() } }
}

import SwiftUIWeb
import SwiftUIWebBrowser
import ClipPlayer

// The browser host: only the entry point. The whole app is ClipPlayerRootView from Sources/ClipPlayer.
@main
struct ClipPlayerWebApp: BrowserApp {
    var body: some View { WindowGroup { ClipPlayerRootView() } }
}

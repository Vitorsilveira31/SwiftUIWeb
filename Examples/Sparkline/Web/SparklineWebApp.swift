import SwiftUIWeb
import SwiftUIWebBrowser
import Sparkline

// The browser host: only the entry point. The whole app is SparklineRootView from Sources/Sparkline.
@main
struct SparklineWebApp: BrowserApp {
    var body: some View { WindowGroup { SparklineRootView() } }
}

import SwiftUIWeb
import SwiftUIWebBrowser
import TextStudies

// The browser host: only the entry point. The whole app is TextStudiesRootView from Sources/TextStudies.
@main
struct TextStudiesWebApp: BrowserApp {
    var body: some View { WindowGroup { TextStudiesRootView() } }
}

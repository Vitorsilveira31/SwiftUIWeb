import SwiftUIWeb
import SwiftUIWebBrowser
import MarkdownReader

// The browser host: only the entry point. The whole app is MarkdownReaderRootView from Sources/MarkdownReader.
@main
struct MarkdownReaderWebApp: BrowserApp {
    var body: some View { WindowGroup { MarkdownReaderRootView() } }
}

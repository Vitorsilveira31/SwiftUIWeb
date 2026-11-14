import SwiftUIWeb
import SwiftUIWebBrowser
import PhotoEditor

// The browser host: only the entry point. The whole app is PhotoEditorRootView from Sources/PhotoEditor.
@main
struct PhotoEditorWebApp: BrowserApp {
    var body: some View { WindowGroup { PhotoEditorRootView() } }
}

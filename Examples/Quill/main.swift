import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct Quill: BrowserApp {
  var body: some View {
    WindowGroup { QuillRootView(dependencies: .live) }
  }
}

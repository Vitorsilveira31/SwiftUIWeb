import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct LazyCellStateApp: BrowserApp {
  var body: some View {
    WindowGroup { LazyCellStateRootView() }
  }
}

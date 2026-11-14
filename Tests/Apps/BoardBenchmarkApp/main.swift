import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct BoardBenchmarkApp: BrowserApp {
  var body: some View {
    WindowGroup { BoardRootView() }
  }
}

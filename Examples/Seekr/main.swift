import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct Seekr: BrowserApp {
  var body: some View {
    WindowGroup { SeekrRootView(dependencies: .live) }
  }
}

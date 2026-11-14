import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct Lumio: BrowserApp {
  var body: some View {
    WindowGroup { LumioRootView(dependencies: .live) }
  }
}

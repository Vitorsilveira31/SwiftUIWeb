import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct Neighborly: BrowserApp {
  var body: some View {
    WindowGroup { NeighborlyRootView(dependencies: .live) }
  }
}

import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct Stayly: BrowserApp {
  var body: some View {
    WindowGroup { StaylyRootView(dependencies: .live) }
  }
}

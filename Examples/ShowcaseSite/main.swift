import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct ShowcaseSite: BrowserApp {
  var body: some View {
    WindowGroup { SiteRootView(dependencies: .live) }
  }
}

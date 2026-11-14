import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct ViewTransitionApp: BrowserApp {
  var body: some View {
    WindowGroup { ViewTransitionRootView() }
  }
}

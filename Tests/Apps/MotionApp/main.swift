import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct MotionApp: BrowserApp {
  var body: some View {
    WindowGroup { MotionRootView() }
  }
}

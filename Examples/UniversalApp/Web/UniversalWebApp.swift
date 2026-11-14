import SwiftUIWeb
import SwiftUIWebBrowser
import Shared

/// The web target owns only its browser entry point. The entire screen comes
/// from the same SharedRootView used by the Darwin Xcode target.
@main
struct UniversalWebApp: BrowserApp {
  var body: some View {
    WindowGroup {
      SharedRootView()
        .accessibilityIdentifier("universal-app-web-root")
    }
  }
}

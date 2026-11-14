import SwiftUIWeb
import SwiftUIWebBrowser

@main
struct Mailo: BrowserApp {
  var body: some View {
    WindowGroup { MailoRootView(dependencies: .live) }
  }
}

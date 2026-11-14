import SwiftUIWeb
import SwiftUIWebBrowser
import SwiftUIWebWeb

/// A focused example of the SwiftUIWebWeb module. The inline HTML has no base URL, so its relative links resolve against
/// the app's own origin and the browser adapter can report the navigations. The second view loads a remote URL to show
/// the cross-origin boundary: the iframe still works, but its DOM cannot be read.
@main
private struct WebKitExample: BrowserApp {
  @State private var page = WebContentModel(
    html: "<h1>Embedded HTML</h1><p><a href='/next'>Same-origin link</a></p>"
  )
  @State private var lastNavigation = "Not navigated yet"

  var body: some View {
    WindowGroup {
      VStack(alignment: .leading, spacing: 12) {
        Text("SwiftUIWebWeb")
          .font(.title)
        Text(lastNavigation)
          .font(.caption)
        WebContentView(
          model: page,
          configuration: WebContentConfiguration(
            title: "Embedded example",
            externalLinkBehavior: .openExternally
          ),
          onNavigation: { navigation in
            lastNavigation = navigation.url?.absoluteString ?? "HTML document"
          },
          onExternalLink: { url in
            lastNavigation = "External: \(url.absoluteString)"
          }
        )
        .frame(height: 280)
        Text("Cross-origin URL (the parent cannot inspect its DOM or links)")
          .font(.caption)
        WebContentView(
          url: "https://example.com",
          title: "Cross-origin example",
          externalLinkBehavior: .openExternally
        )
        .frame(height: 180)
        HStack {
          Button("Back") { page.goBack() }
          Button("Forward") { page.goForward() }
          Button("Reload") { page.reload() }
          if page.navigationState.isLoading { ProgressView() }
        }
      }
      .padding()
    }
  }
}

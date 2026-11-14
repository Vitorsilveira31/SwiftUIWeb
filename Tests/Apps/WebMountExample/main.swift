import SwiftUIWeb
@_spi(WebMount) import SwiftUIWebBrowser

/// A deliberately tiny controller used as an integration fixture. It writes
/// browser-owned state only during mount; typing into the input and pressing
/// the SwiftUI button below demonstrates that an unrelated Fiber update does
/// not recreate the native element.
private final class StatefulInputController: WebMountController {
  func mount(element: WebElementHandle, token: String) {
    if element.attribute("data-demo-mounted") == nil {
      element.setAttribute("data-demo-mounted", "true")
      element.setAttribute("data-demo-token", token)
      element.value = "Type here; this value belongs to the DOM"
    }
  }

  func update(element: WebElementHandle, token: String) {
    let count = Int(element.attribute("data-demo-updates") ?? "0") ?? 0
    element.setAttribute("data-demo-updates", String(count + 1))
    element.setAttribute("data-demo-token", token)
  }

  func unmount() {}
  func dispose() {}
}

@main
private struct WebMountExample: BrowserApp {
  // Keep the registration alive for the lifetime of the application. The
  // controller itself is still owned by WebMountRegistry per Fiber token.
  private static let registration = WebMountRegistry.shared.register(key: "stateful-input") { _, _ in
    StatefulInputController()
  }

  @State private var unrelatedUpdates = 0

  var body: some View {
    WindowGroup {
      VStack {
        Text("Incremental DOM mount fixture")
        Text("Type in the field, then update unrelated Swift state repeatedly.")
        WebMountSurface(tag: "input", key: "stateful-input")
        Button("Update Swift state") { unrelatedUpdates += 1 }
        Text("Unrelated updates: \(unrelatedUpdates)")
        Text("The input's value and data-demo-mounted marker should remain unchanged.")
      }
    }
  }
}

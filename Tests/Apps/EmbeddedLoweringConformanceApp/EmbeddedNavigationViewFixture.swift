import SwiftUIWeb

/// The legacy `NavigationView` is laid out as a NavigationStack: its root, then after a push the destination below a bar
/// with the back button, the root hidden. CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedNavigationViewFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      NavigationView {
        VStack(alignment: .leading, spacing: 8) {
          Text("Legacy root")
          NavigationLink("Open detail") { Text("Detail screen").frame(width: 200, height: 60).background(Color.blue.opacity(0.2)) }
        }
      }
      .frame(width: 360, height: 180)
    }
    .padding(16)
  }
}

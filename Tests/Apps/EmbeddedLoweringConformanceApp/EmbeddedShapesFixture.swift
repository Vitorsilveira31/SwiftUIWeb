import SwiftUIWeb

/// A Section whose header and footer hold two views each (a padding around a vstack of its own), and chains of frames that one CSS box cannot hold, which keep an element each. CSS layout must
/// lay it out (`Tools/test-css-layout-fixtures-browser.mjs`), on WebKit too.
struct EmbeddedShapesFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Section {
        Text("Section row")
      } header: {
        Text("Section header")
        Text("A second header line")
      } footer: {
        Text("Section footer")
        Text("A second footer line")
      }
      Text("Three frames").frame(width: 30).frame(width: 60).frame(width: 100).background(.green)
      Text("A padding inside a frame").frame(width: 60).padding(8).frame(width: 120).frame(maxWidth: .infinity, alignment: .leading).background(.green)
    }
    .padding(16)
  }
}

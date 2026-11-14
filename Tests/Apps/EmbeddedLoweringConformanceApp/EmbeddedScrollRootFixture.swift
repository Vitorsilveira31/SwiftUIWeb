import SwiftUIWeb

/// A vertical ScrollView as the application's root view: CSS layout styles it as the window's one scrolling box, and
/// the page's verifier must give it the block Swift sent (not the one of an island the mapper styles).
/// CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedScrollRootFixture: View {
  let onDone: () -> Void

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 8) {
        Button("Return to conformance app") { onDone() }
        ForEach(0..<12, id: \.self) { index in
          Text("Row \(index)").padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.2))
        }
      }
      .padding(16)
    }
  }
}

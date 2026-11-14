import SwiftUIWeb

/// A horizontal shelf of chips, wider together than the window, inside a LazyVStack in a vertical ScrollView (the
/// format tabs of a details screen). The shelf is one of the lazy stack's rows, not a lazy collection of its own: every
/// chip is rendered.
/// CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedLazyShelfFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          Text("Formats")
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(0..<12, id: \.self) { index in
                Text("Format chip \(index)").padding(.horizontal, 14).padding(.vertical, 8).background(Color.gray.opacity(0.2))
              }
            }
            .padding(.horizontal, 16)
          }
          Text("Below the shelf")
        }
      }
      .frame(height: 300)
    }
    .padding(16)
  }
}

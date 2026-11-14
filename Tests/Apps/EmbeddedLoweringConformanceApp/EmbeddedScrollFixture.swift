import SwiftUIWeb

/// ScrollViews sized as SwiftUI sizes them: along the axis they scroll they take their proposal; across it they are as
/// large as their content, which they hold at their origin, and their parent places them. A horizontal shelf in a
/// VStack is as tall as its cards, which keep their own widths past the viewport; a vertical ScrollView of a short text
/// is as wide as the text, centred by its frame.
/// CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedScrollFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Text("Shelf")
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(0..<6, id: \.self) { _ in Color.teal.frame(width: 120, height: 80) }
          // Cards as wide as their text, wider together than the viewport: offered no width, they keep their own.
          ForEach(0..<8, id: \.self) { index in
            Text("A card with a longer title \(index)").padding(8).background(Color.gray.opacity(0.2))
          }
        }
      }
      ScrollView {
        Text("A short text")
      }
      .frame(maxWidth: .infinity)
      .frame(height: 120)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          Text("Rows that fill the width")
          Text("Second row")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 80)
    }
    .padding(16)
  }
}

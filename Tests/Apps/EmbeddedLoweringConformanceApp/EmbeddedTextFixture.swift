import SwiftUIWeb

/// A `TextField` takes the width its HStack gives it, with the default style and with `.plain`, as in SwiftUI; a text
/// with `lineLimit(2)` or `lineLimit(3)` is at most that many lines tall; a Link is as wide as its label. CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedTextFixture: View {
  let onDone: () -> Void
  @State private var query = ""
  @State private var plain = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      HStack(spacing: 8) {
        Text("Search")
        TextField("Search works", text: $query)
      }
      .frame(width: 420)
      HStack(spacing: 8) {
        Text("Plain")
        TextField("A plain field", text: $plain).textFieldStyle(.plain)
      }
      .frame(width: 420)
      Text("A long title that wraps to more than two lines when it is given only this narrow width to fill")
        .lineLimit(2)
        .frame(width: 200, alignment: .leading)
      Text("A long title that wraps to more than three lines when it is given only this narrow width to fill and more")
        .lineLimit(3)
        .frame(width: 160, alignment: .leading)
      Text("A short one").lineLimit(2)
      // A Link is as wide as its label: centred by its VStack, as Food Truck's "Other data sources".
      VStack {
        Color.gray.frame(width: 20, height: 20)
        Link("Other data sources", destination: URL(string: "https://example.com/attribution")!)
      }
      .frame(width: 420)
    }
    .padding(16)
  }
}

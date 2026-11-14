import SwiftUIWeb

/// Several principal toolbar items sit side by side, with no gap, as a group centred on the bar (not between the side
/// items), with a leading and a trailing item of different widths, with and without a title; beside a long leading item
/// the group starts 8 px after it. Several items on a side too, a track each, 8 px apart: with principal items between blocks of
/// items of equal width, with no principal item, and with one. (Between blocks of unequal width the mapper centres the group
/// between them: `test-css-layout-roots.mjs` checks that placement, which this
/// fixture leaves out.) CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedPrincipalFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      stack(title: nil, leading: "Back", trailing: "Done")
      stack(title: "Orders", leading: "Back", trailing: "Done")
      stack(title: nil, leading: "Back to the list of orders", trailing: "Done")
      stack(title: nil, leading: "A", leading2: "B", trailing: "C", trailing2: "D", width: 56, principals: 2)
      stack(title: "Orders", leading: "Back", leading2: "Edit", trailing: "Done", trailing2: "More options", principals: 0)
      stack(title: "Orders", leading: "Back", leading2: "Edit", trailing: "Done", trailing2: "More options", principals: 1)
    }
    .padding(16)
  }

  private func stack(title: String?, leading: String, leading2: String? = nil, trailing: String, trailing2: String? = nil, width: Double? = nil, principals: Int = 2) -> some View {
    NavigationStack {
      Text("Screen")
        .navigationTitle(title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) { Button(leading) {}.frame(width: width) }
          if let leading2 {
            ToolbarItem(placement: .navigationBarLeading) { Button(leading2) {}.frame(width: width) }
          }
          if principals > 0 {
            ToolbarItem(placement: .principal) { Text("First") }
          }
          if principals > 1 {
            ToolbarItem(placement: .principal) { Text("Second item") }
          }
          ToolbarItem(placement: .navigationBarTrailing) { Button(trailing) {}.frame(width: width) }
          if let trailing2 {
            ToolbarItem(placement: .navigationBarTrailing) { Button(trailing2) {}.frame(width: width) }
          }
        }
    }
    .frame(width: leading2 == nil ? 460 : 720, height: 80)
  }
}

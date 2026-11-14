import SwiftUIWeb

/// The live `ViewThatFits` of the catalog: the long label is shown when the frame is wide enough for it, the short one otherwise.
struct ViewThatFitsCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    ViewThatFits(in: .horizontal) {
      Text("A long label that needs the full width")
      Text("Short label")
    }
    .frame(width: values.number("width"))
    .background(Color.blue.opacity(0.15))
  }
}

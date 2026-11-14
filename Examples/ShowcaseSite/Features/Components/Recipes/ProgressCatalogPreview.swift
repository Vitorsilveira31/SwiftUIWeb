import SwiftUIWeb

/// The live `ProgressView` of the catalog, determinate or spinning.
struct ProgressCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Group {
      if values.bool("determinate") {
        ProgressView(value: values.number("value"))
      } else {
        ProgressView()
      }
    }
    .tint(CatalogTokens.color(values.choice("tint", in: CatalogTokens.colors)))
    .frame(maxWidth: 320)
  }
}

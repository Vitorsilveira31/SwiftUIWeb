import SwiftUIWeb

/// The live `Text` of the catalog, styled by the knob values.
struct TextCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Text(values.text("content"))
      .font(CatalogTokens.font(values.choice("font", in: CatalogTokens.fonts)))
      .fontWeight(values.bool("bold") ? .bold : .regular)
      .foregroundStyle(CatalogTokens.color(values.choice("color", in: CatalogTokens.colors)))
  }
}

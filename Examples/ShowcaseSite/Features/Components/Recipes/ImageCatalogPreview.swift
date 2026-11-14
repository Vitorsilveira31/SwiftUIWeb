import SwiftUIWeb

/// The live SF Symbol `Image` of the catalog.
struct ImageCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Image(systemName: values.choice("symbol", in: ImageCatalogRecipe.symbols))
      .font(.system(size: values.number("size")))
      .foregroundStyle(CatalogTokens.color(values.choice("color", in: CatalogTokens.colors)))
  }
}

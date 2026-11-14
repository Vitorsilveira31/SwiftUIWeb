import SwiftUIWeb

/// The live `ContentUnavailableView` of the catalog, with or without its description.
struct ContentUnavailableViewCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Group {
      if values.bool("description") {
        ContentUnavailableView(
          values.text("title"),
          systemImage: values.choice("symbol", in: ContentUnavailableViewCatalogRecipe.symbols),
          description: Text(ContentUnavailableViewCatalogRecipe.descriptionText)
        )
      } else {
        ContentUnavailableView(
          values.text("title"),
          systemImage: values.choice("symbol", in: ContentUnavailableViewCatalogRecipe.symbols)
        )
      }
    }
    .frame(maxWidth: 360)
  }
}

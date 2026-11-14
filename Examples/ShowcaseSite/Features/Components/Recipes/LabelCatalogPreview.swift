import SwiftUIWeb

/// The live `Label` of the catalog, in the style the knob picks.
struct LabelCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Label(values.text("title"), systemImage: values.choice("symbol", in: LabelCatalogRecipe.symbols))
      .font(.title3)
  }
}

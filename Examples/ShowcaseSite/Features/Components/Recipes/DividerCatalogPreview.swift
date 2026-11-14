import SwiftUIWeb

/// The live `Divider` of the catalog, between two texts in the stack the knob picks.
struct DividerCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    if values.choice("direction", in: DividerCatalogRecipe.directions) == "HStack" {
      HStack {
        Text("A")
        Divider().padding(values.number("padding"))
        Text("B")
      }
    } else {
      VStack {
        Text("A")
        Divider().padding(values.number("padding"))
        Text("B")
      }
    }
  }
}

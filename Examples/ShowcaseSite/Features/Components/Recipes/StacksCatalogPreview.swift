import SwiftUIWeb

/// The live stack of the catalog: three boxes of different sizes in a `VStack` or an `HStack`.
struct StacksCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    if values.choice("direction", in: StacksCatalogRecipe.directions) == "VStack" {
      VStack(alignment: StacksCatalogRecipe.horizontal(values.choice("alignment", in: StacksCatalogRecipe.alignments)), spacing: values.number("spacing")) {
        StacksCatalogBoxes()
      }
    } else {
      HStack(alignment: StacksCatalogRecipe.vertical(values.choice("alignment", in: StacksCatalogRecipe.alignments)), spacing: values.number("spacing")) {
        StacksCatalogBoxes()
      }
    }
  }
}

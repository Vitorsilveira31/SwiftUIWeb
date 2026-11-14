import SwiftUIWeb

/// The live `ZStack` of the catalog: three boxes stacked in the alignment the knob picks, the front one pushed sideways.
struct ZStackCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    switch values.choice("alignment", in: ZStackCatalogRecipe.alignments) {
    case "topLeading":
      ZStack(alignment: .topLeading) {
        ZStackCatalogBoxes(frontOffset: values.number("offset"))
      }
    case "bottomTrailing":
      ZStack(alignment: .bottomTrailing) {
        ZStackCatalogBoxes(frontOffset: values.number("offset"))
      }
    default:
      ZStack(alignment: .center) {
        ZStackCatalogBoxes(frontOffset: values.number("offset"))
      }
    }
  }
}

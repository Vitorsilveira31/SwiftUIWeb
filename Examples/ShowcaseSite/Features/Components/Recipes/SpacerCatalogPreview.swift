import SwiftUIWeb

/// The live `Spacer` of the catalog: two boxes pushed to the edges of a row, with the minimum gap the knob sets.
struct SpacerCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    HStack {
      SpacerCatalogBox(isFixed: values.bool("fixed"))
      Spacer(minLength: values.number("minLength"))
      SpacerCatalogBox(isFixed: values.bool("fixed"))
    }
    .frame(maxWidth: 320)
  }
}

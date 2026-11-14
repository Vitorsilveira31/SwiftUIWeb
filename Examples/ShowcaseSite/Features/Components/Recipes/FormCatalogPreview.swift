import SwiftUIWeb

/// The live `Form` of the catalog: one section, under the header the knob gives, holding the rows the knob asks for.
struct FormCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Form {
      Section(values.text("header")) {
        FormCatalogRows(count: Int(values.number("rows")))
      }
    }
    .frame(maxWidth: 360)
  }
}

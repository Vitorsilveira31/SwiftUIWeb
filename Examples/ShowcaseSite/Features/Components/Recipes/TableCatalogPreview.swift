import SwiftUIWeb

/// The live `Table` of the catalog, in the table style the knob picks, with as many rows as the rows knob sets.
struct TableCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Group {
      switch values.choice("style", in: TableCatalogRecipe.styles) {
      case "inset":
        TableCatalogContent(count: Int(values.number("rows"))).tableStyle(.inset)
      case "bordered":
        TableCatalogContent(count: Int(values.number("rows"))).tableStyle(.bordered)
      default:
        TableCatalogContent(count: Int(values.number("rows"))).tableStyle(.automatic)
      }
    }
    .frame(maxWidth: 360)
  }
}

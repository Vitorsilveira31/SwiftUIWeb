import SwiftUIWeb

/// The live `Grid` of the catalog: rows of `GridRow`s, each with as many cells as the columns knob sets.
struct GridCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Grid(horizontalSpacing: values.number("spacing"), verticalSpacing: values.number("spacing")) {
      ForEach(1...Int(values.number("rows")), id: \.self) { row in
        GridRow {
          ForEach(1...Int(values.number("columns")), id: \.self) { column in
            Text("\(row).\(column)").padding(8).background(Color.blue.opacity(0.12))
          }
        }
      }
    }
    .frame(maxWidth: 360)
  }
}

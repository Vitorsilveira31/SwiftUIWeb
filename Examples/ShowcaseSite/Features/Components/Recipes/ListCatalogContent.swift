import SwiftUIWeb

/// The `List` itself, before a style is applied to it: one row of text for each number the rows knob sets.
struct ListCatalogContent: View {
  let values: CatalogKnobValues

  var body: some View {
    List {
      ForEach(1...Int(values.number("rows")), id: \.self) { number in Text("Row \(number)") }
    }
  }
}

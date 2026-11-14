import SwiftUIWeb

/// The live lazy stack of the catalog: a `LazyVStack` in a vertical `ScrollView`, or a `LazyHStack` in a horizontal one.
struct LazyStacksCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    if values.choice("direction", in: LazyStacksCatalogRecipe.directions) == "LazyVStack" {
      ScrollView(.vertical) {
        LazyVStack(spacing: values.number("spacing")) {
          ForEach(1...Int(values.number("rows")), id: \.self) { number in Text("Row \(number)") }
        }
      }
      .frame(height: 160)
      .frame(maxWidth: 360)
    } else {
      ScrollView(.horizontal) {
        LazyHStack(spacing: values.number("spacing")) {
          ForEach(1...Int(values.number("rows")), id: \.self) { number in Text("Row \(number)") }
        }
      }
      .frame(height: 160)
      .frame(maxWidth: 360)
    }
  }
}

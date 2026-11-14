import SwiftUIWeb

/// The live `LazyVGrid` of the catalog inside a vertical `ScrollView`: flexible columns from the knobs, or adaptive ones.
struct LazyVGridCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    if values.choice("sizing", in: LazyVGridCatalogRecipe.sizings) == "flexible" {
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: Int(values.number("columns"))), spacing: values.number("spacing")) {
          ForEach(1...24, id: \.self) { number in
            Text("Item \(number)").padding(12).background(Color.blue.opacity(0.12))
          }
        }
      }
      .frame(height: 220)
      .frame(maxWidth: 360)
    } else {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: values.number("spacing")) {
          ForEach(1...24, id: \.self) { number in
            Text("Item \(number)").padding(12).background(Color.blue.opacity(0.12))
          }
        }
      }
      .frame(height: 220)
      .frame(maxWidth: 360)
    }
  }
}

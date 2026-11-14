import SwiftUIWeb

/// The live `ScrollView` of the catalog: twenty items on the axis the knob picks, in a fixed-height area so they scroll.
struct ScrollViewCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    if values.choice("axis", in: ScrollViewCatalogRecipe.axes) == "vertical" {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(1...20, id: \.self) { number in Text("Item \(number)") }
        }
      }
      .scrollIndicators(values.bool("indicators") ? .visible : .hidden)
      .frame(height: 160)
      .frame(maxWidth: 360)
    } else {
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(1...20, id: \.self) { number in Text("Item \(number)") }
        }
      }
      .scrollIndicators(values.bool("indicators") ? .visible : .hidden)
      .frame(height: 160)
      .frame(maxWidth: 360)
    }
  }
}

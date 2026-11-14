import SwiftUIWeb

/// The live `Slider` of the catalog with its current value beside it.
struct SliderCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var level = 30.0

  var body: some View {
    HStack(spacing: 12) {
      if values.number("step") > 0 {
        Slider(value: $level, in: 0...values.number("maximum"), step: values.number("step"))
      } else {
        Slider(value: $level, in: 0...values.number("maximum"))
      }
      Text("\(Int(level))").monospacedDigit().frame(minWidth: 36)
    }
    .frame(maxWidth: 320)
  }
}

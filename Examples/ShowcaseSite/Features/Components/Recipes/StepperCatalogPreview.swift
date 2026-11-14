import SwiftUIWeb

/// The live `Stepper` of the catalog, counting between zero and the upper bound.
struct StepperCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var count = 2

  var body: some View {
    Stepper(
      "\(values.text("label")): \(count)",
      value: $count,
      in: 0...Int(values.number("maximum")),
      step: Int(values.number("step"))
    )
    .frame(maxWidth: 320)
  }
}

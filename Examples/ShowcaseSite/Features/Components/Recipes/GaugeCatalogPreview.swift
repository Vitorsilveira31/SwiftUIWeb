import SwiftUIWeb

/// The live `Gauge` of the catalog: a meter for the value the knob sets, with the label beside it.
struct GaugeCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Gauge(value: values.number("value")) {
      Text(values.text("label"))
    }
    .frame(maxWidth: 320)
  }
}

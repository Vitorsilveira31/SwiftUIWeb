import SwiftUIWeb

/// The live `Toggle` of the catalog, holding its own on/off state.
struct ToggleCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var isOn = true

  var body: some View {
    Toggle(values.text("label"), isOn: $isOn)
      .disabled(values.bool("disabled"))
      .frame(maxWidth: 280)
  }
}

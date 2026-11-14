import SwiftUIWeb

/// The live `ControlGroup` of the catalog; the number under it is the last button pressed, zero before any press.
struct ControlGroupCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var picked = 0

  var body: some View {
    VStack(spacing: 8) {
      ControlGroupCatalogContent(title: values.text("label"), count: Int(values.number("count")), picked: $picked)
      Text("\(picked)").font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: 320)
  }
}

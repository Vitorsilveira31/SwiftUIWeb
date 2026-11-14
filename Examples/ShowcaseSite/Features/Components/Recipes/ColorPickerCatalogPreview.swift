import SwiftUIWeb

/// The live `ColorPicker` of the catalog, with a swatch beside it that takes the chosen color.
struct ColorPickerCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var color = Color.blue

  var body: some View {
    HStack(spacing: 12) {
      ColorPicker(values.text("label"), selection: $color, supportsOpacity: values.bool("opacity"))
      RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 48, height: 24)
    }
    .frame(maxWidth: 320)
  }
}

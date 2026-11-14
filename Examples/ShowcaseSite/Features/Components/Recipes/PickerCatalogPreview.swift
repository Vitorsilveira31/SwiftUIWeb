import SwiftUIWeb

/// The live `Picker` of the catalog, in the style the knob picks.
struct PickerCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var selection = 1

  var body: some View {
    Group {
      switch values.choice("style", in: PickerCatalogRecipe.styles) {
      case "segmented":
        PickerCatalogContent(label: values.text("label"), count: Int(values.number("count")), selection: $selection)
          .pickerStyle(.segmented)
      case "inline":
        PickerCatalogContent(label: values.text("label"), count: Int(values.number("count")), selection: $selection)
          .pickerStyle(.inline)
      default:
        PickerCatalogContent(label: values.text("label"), count: Int(values.number("count")), selection: $selection)
          .pickerStyle(.menu)
      }
    }
    .frame(maxWidth: 360)
  }
}

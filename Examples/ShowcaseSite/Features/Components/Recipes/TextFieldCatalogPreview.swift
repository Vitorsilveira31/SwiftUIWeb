import SwiftUIWeb

/// The live `TextField` of the catalog, in the style the knob picks, echoing what is typed.
struct TextFieldCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      switch values.choice("style", in: TextFieldCatalogRecipe.styles) {
      case "roundedBorder":
        TextFieldCatalogContent(prompt: values.text("prompt"), isDisabled: values.bool("disabled"), text: $text)
          .textFieldStyle(.roundedBorder)
      case "plain":
        TextFieldCatalogContent(prompt: values.text("prompt"), isDisabled: values.bool("disabled"), text: $text)
          .textFieldStyle(.plain)
      default:
        TextFieldCatalogContent(prompt: values.text("prompt"), isDisabled: values.bool("disabled"), text: $text)
          .textFieldStyle(.automatic)
      }
      Text(text).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: 320)
  }
}

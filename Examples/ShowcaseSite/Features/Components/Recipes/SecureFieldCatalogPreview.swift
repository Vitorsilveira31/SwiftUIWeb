import SwiftUIWeb

/// The live `SecureField` of the catalog, in the style the knob picks; what is typed stays hidden.
struct SecureFieldCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var password = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      switch values.choice("style", in: SecureFieldCatalogRecipe.styles) {
      case "plain":
        content.textFieldStyle(.plain)
      default:
        content.textFieldStyle(.automatic)
      }
    }
    .frame(maxWidth: 320)
  }

  private var content: SecureFieldCatalogContent {
    SecureFieldCatalogContent(
      prompt: values.text("prompt"),
      isDisabled: values.bool("disabled"),
      password: $password
    )
  }
}

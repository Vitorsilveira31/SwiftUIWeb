import SwiftUIWeb

/// The `TextField` itself, before a style is applied to it.
struct TextFieldCatalogContent: View {
  let prompt: String
  let isDisabled: Bool
  @Binding var text: String

  var body: some View {
    TextField(prompt, text: $text).disabled(isDisabled)
  }
}

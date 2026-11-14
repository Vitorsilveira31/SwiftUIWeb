import SwiftUIWeb

/// The `SecureField` itself, before a style is applied to it; its prompt and disabled state come from the knobs.
struct SecureFieldCatalogContent: View {
  let prompt: String
  let isDisabled: Bool
  @Binding var password: String

  var body: some View {
    SecureField("Password", text: $password, prompt: Text(prompt)).disabled(isDisabled)
  }
}

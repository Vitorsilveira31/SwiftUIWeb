import SwiftUIWeb

/// One `TextField` row of the form, holding the text typed in it.
struct FormCatalogTextRow: View {
  let number: Int
  @State private var text = ""

  var body: some View {
    TextField("Option \(number)", text: $text)
  }
}

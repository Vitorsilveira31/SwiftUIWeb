import SwiftUIWeb

/// One `Toggle` row of the form, holding its own on/off state.
struct FormCatalogToggleRow: View {
  let number: Int
  @State private var isOn = false

  var body: some View {
    Toggle("Option \(number)", isOn: $isOn)
  }
}

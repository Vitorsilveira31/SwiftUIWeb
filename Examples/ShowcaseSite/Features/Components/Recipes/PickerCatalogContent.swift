import SwiftUIWeb

/// The `Picker` itself, before a style is applied to it.
struct PickerCatalogContent: View {
  let label: String
  let count: Int
  @Binding var selection: Int

  var body: some View {
    Picker(label, selection: $selection) {
      ForEach(1...count, id: \.self) { number in Text("Option \(number)").tag(number) }
    }
  }
}

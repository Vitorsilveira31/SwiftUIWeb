import SwiftUIWeb

/// The `Menu` itself: a title that opens one button per item; picking a button records its number.
struct MenuCatalogContent: View {
  let title: String
  let count: Int
  @Binding var picked: Int

  var body: some View {
    Menu(title) {
      ForEach(1...count, id: \.self) { number in
        Button("Item \(number)") { picked = number }
      }
    }
  }
}

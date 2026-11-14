import SwiftUIWeb

/// The `ControlGroup` itself: one button per item, in a row; pressing a button records its number.
struct ControlGroupCatalogContent: View {
  let title: String
  let count: Int
  @Binding var picked: Int

  var body: some View {
    ControlGroup(title) {
      ForEach(1...count, id: \.self) { number in
        Button("\(number)") { picked = number }
      }
    }
  }
}

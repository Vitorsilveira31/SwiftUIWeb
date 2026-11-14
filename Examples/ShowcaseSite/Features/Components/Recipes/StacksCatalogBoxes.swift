import SwiftUIWeb

/// Three colored boxes of different sizes, to make alignment and spacing visible.
struct StacksCatalogBoxes: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 6).fill(Color.blue).frame(width: 60, height: 36)
    RoundedRectangle(cornerRadius: 6).fill(Color.green).frame(width: 90, height: 48)
    RoundedRectangle(cornerRadius: 6).fill(Color.orange).frame(width: 40, height: 28)
  }
}

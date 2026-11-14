import SwiftUIWeb

/// Three boxes of different sizes stacked on each other; the front one is pushed sideways by the offset knob.
struct ZStackCatalogBoxes: View {
  let frontOffset: Double

  var body: some View {
    RoundedRectangle(cornerRadius: 6).fill(Color.blue).frame(width: 140, height: 90)
    RoundedRectangle(cornerRadius: 6).fill(Color.green).frame(width: 100, height: 60)
    RoundedRectangle(cornerRadius: 6).fill(Color.orange).frame(width: 60, height: 36).offset(x: frontOffset)
  }
}

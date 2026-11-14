import SwiftUIWeb

/// The Seekr mark: a gradient tile with a ring and its handle, a lens over the search.
struct SeekrMark: View {
  var size: CGFloat = 32

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28).fill(SeekrPalette.brand)
      Circle().stroke(Color.white, lineWidth: size * 0.1).frame(width: size * 0.5, height: size * 0.5).offset(x: -size * 0.07, y: -size * 0.07)
      Capsule().fill(Color.white).frame(width: size * 0.3, height: size * 0.11).rotationEffect(.degrees(45)).offset(x: size * 0.2, y: size * 0.2)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

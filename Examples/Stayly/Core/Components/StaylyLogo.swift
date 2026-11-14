import SwiftUIWeb

/// The Stayly mark: a teal tile with a roof over a door, and a sun above it. Drawn with shapes, so it needs no picture.
struct StaylyLogo: View {
  var size: CGFloat = 32

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28).fill(StaylyPalette.brand)
      Rectangle().fill(Color.white).frame(width: size * 0.44, height: size * 0.44).rotationEffect(.degrees(45)).offset(y: -size * 0.04)
      RoundedRectangle(cornerRadius: size * 0.04).fill(Color.white).frame(width: size * 0.38, height: size * 0.3).offset(y: size * 0.2)
      RoundedRectangle(cornerRadius: size * 0.03).fill(StaylyPalette.teal).frame(width: size * 0.1, height: size * 0.16).offset(y: size * 0.24)
      Circle().fill(StaylyPalette.gold).frame(width: size * 0.14, height: size * 0.14).offset(x: size * 0.26, y: -size * 0.3)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

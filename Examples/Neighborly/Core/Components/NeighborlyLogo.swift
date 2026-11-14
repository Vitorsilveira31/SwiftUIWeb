import SwiftUIWeb

/// The Neighborly mark: a teal tile with two neighbors side by side, one in front of the other, over a shared ground line.
struct NeighborlyLogo: View {
  var size: CGFloat = 32

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28).fill(NeighborlyPalette.brand)
      Circle().fill(NeighborlyPalette.sun)
        .frame(width: size * 0.34, height: size * 0.34)
        .offset(x: -size * 0.13, y: -size * 0.12)
      Circle().fill(Color.white)
        .frame(width: size * 0.4, height: size * 0.4)
        .offset(x: size * 0.1, y: -size * 0.04)
      Capsule().fill(Color.white)
        .frame(width: size * 0.66, height: size * 0.22)
        .offset(y: size * 0.24)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

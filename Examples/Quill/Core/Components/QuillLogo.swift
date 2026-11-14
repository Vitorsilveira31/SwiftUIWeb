import SwiftUIWeb

/// The Quill mark: a white feather on an ink tile, with a teal dot for the nib.
struct QuillLogo: View {
  var size: CGFloat = 32

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28).fill(QuillPalette.ink)
      Capsule()
        .fill(Color.white)
        .frame(width: size * 0.2, height: size * 0.62)
        .rotationEffect(.degrees(35))
        .offset(x: size * 0.08, y: -size * 0.04)
      Circle()
        .fill(QuillPalette.teal)
        .frame(width: size * 0.2, height: size * 0.2)
        .offset(x: -size * 0.2, y: size * 0.2)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

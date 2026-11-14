import SwiftUIWeb

/// The Lumio mark: a lit window, a warm gradient tile with a ring of light and a bright center.
struct LumioLogo: View {
  var size: CGFloat = 32

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28).fill(LumioPalette.brand)
      Circle().stroke(Color.white, lineWidth: size * 0.09).frame(width: size * 0.56, height: size * 0.56)
      Circle().fill(Color.white).frame(width: size * 0.2, height: size * 0.2)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

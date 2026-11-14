import SwiftUIWeb

/// The Mailo mark: a white envelope under a rising sun, on a warm tile.
struct MailoLogo: View {
  var size: CGFloat = 32

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.26).fill(MailoPalette.mark)
      VStack(spacing: size * 0.05) {
        Circle().fill(Color.white).frame(width: size * 0.24, height: size * 0.24)
        ZStack {
          RoundedRectangle(cornerRadius: size * 0.05).fill(Color.white).frame(width: size * 0.6, height: size * 0.4)
          Rectangle().fill(MailoPalette.coral).frame(width: size * 0.5, height: size * 0.035).offset(y: -size * 0.08)
        }
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

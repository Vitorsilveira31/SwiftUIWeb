import SwiftUIWeb

/// A person's picture in a circle, with the brand ring around it when they have something new.
struct LumioAvatar: View {
  let user: LumioUser
  var size: CGFloat = 36
  var ring = false

  var body: some View {
    Image(user.avatarURL, alt: user.name)
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(Circle())
      .padding(ring ? 3 : 0)
      .overlay { if ring { Circle().stroke(LumioPalette.brand, lineWidth: 2.5) } }
  }
}

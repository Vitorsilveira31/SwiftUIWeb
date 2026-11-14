import SwiftUIWeb

/// A neighbor's picture in a circle, with a teal ring around it when they are the one in focus.
struct NeighborlyAvatar: View {
  let user: NeighborlyUser
  var size: CGFloat = 36
  var ring = false

  var body: some View {
    Image(user.avatarURL, alt: user.name)
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(Circle())
      .padding(ring ? 3 : 0)
      .overlay { if ring { Circle().stroke(NeighborlyPalette.teal, lineWidth: 2.5) } }
  }
}

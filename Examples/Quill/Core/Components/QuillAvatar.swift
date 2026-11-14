import SwiftUIWeb

/// A person's picture in a circle.
struct QuillAvatar: View {
  let url: String
  let label: String
  var size: CGFloat = QuillLayout.avatarSize

  var body: some View {
    Image(url, alt: label)
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(Circle())
  }
}

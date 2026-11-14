import SwiftUIWeb

/// The author's name in bold, then what they wrote.
struct PostCaption: View {
  let post: LumioPost

  var body: some View {
    (Text(post.author.username).fontWeight(.semibold) + Text(" ") + Text(post.caption))
      .lineLimit(3)
      .padding(.horizontal, 12)
      .padding(.top, 4)
      .padding(.bottom, 2)
  }
}

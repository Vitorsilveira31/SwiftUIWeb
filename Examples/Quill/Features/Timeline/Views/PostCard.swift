import SwiftUIWeb

/// One post of the timeline: who wrote it, what they wrote and what people did with it, and the line under it. The text opens its thread.
struct PostCard: View {
  let viewModel: TimelineViewModel
  let post: QuillPost

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        QuillAvatar(url: post.author.avatarURL, label: post.author.name)
        VStack(alignment: .leading, spacing: 6) {
          QuillPostHeader(author: post.author)
          Button { viewModel.open(post) } label: {
            Text(post.text).frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          PostActions(viewModel: viewModel, post: post)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      Divider()
    }
  }
}

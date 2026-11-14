import SwiftUIWeb

/// One post: who wrote it, what they wrote, the picture when there is one, the counts, the actions and the comments open under it.
struct PostCard: View {
  let viewModel: FeedViewModel
  let post: NeighborlyPost
  let openPerson: @MainActor @Sendable (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      PostHeader(author: post.author, openPerson: openPerson)
      Text(post.text)
        .lineLimit(8)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let imageURL = post.imageURL {
        Image(imageURL, alt: post.text)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .aspectRatio(1, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      PostCounts(viewModel: viewModel, post: post)
      PostActions(viewModel: viewModel, post: post)
      if viewModel.isThreadOpen(post), let thread = viewModel.thread(for: post) {
        PostThread(viewModel: thread)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NeighborlyPalette.card)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

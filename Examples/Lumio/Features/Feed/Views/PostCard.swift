import SwiftUIWeb

/// One post of the feed: who, the picture, the actions, the likes, the caption, a way into the comments and the line under it.
struct PostCard: View {
  let viewModel: FeedViewModel
  let post: LumioPost

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PostHeader(author: post.author)
      Image(post.imageURL, alt: post.caption)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
      PostActions(viewModel: viewModel, post: post)
      Text(FeedStrings.likes(viewModel.likes(of: post))).fontWeight(.semibold).padding(.horizontal, 12)
      PostCaption(post: post)
      Button { viewModel.commenting = post } label: {
        Text(FeedStrings.viewComments(post.commentCount)).foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 12)
      .padding(.bottom, 12)
      Divider()
    }
  }
}

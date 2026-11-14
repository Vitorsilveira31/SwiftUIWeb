import SwiftUIWeb

/// How many liked the post and how many commented on it, in a line above the actions.
struct PostCounts: View {
  let viewModel: FeedViewModel
  let post: NeighborlyPost

  var body: some View {
    HStack(spacing: 8) {
      Text(FeedStrings.reactions(viewModel.reactions(of: post))).font(.caption).foregroundStyle(.secondary)
      Spacer()
      Text(FeedStrings.comments(viewModel.commentCount(of: post))).font(.caption).foregroundStyle(.secondary)
    }
  }
}

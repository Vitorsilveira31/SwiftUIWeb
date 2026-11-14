import SwiftUIWeb

/// Like, comment, share on the left, save on the right.
struct PostActions: View {
  let viewModel: FeedViewModel
  let post: LumioPost

  var body: some View {
    HStack(spacing: 16) {
      Button { viewModel.toggleLike(post) } label: {
        Image(systemName: viewModel.isLiked(post) ? "heart.fill" : "heart")
          .foregroundStyle(viewModel.isLiked(post) ? LumioPalette.like : Color.primary)
      }
      .accessibilityLabel(viewModel.isLiked(post) ? FeedStrings.unlike : FeedStrings.like)
      Button { viewModel.commenting = post } label: { Image(systemName: "bubble.left") }
        .accessibilityLabel(FeedStrings.comment)
      Button { } label: { Image(systemName: "paperplane") }
        .accessibilityLabel(FeedStrings.share)
      Spacer()
      Button { viewModel.toggleSave(post) } label: { Image(systemName: viewModel.isSaved(post) ? "bookmark.fill" : "bookmark") }
        .accessibilityLabel(viewModel.isSaved(post) ? FeedStrings.unsave : FeedStrings.save)
    }
    .font(.title3)
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

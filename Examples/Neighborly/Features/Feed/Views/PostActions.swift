import SwiftUIWeb

/// Like and comment, side by side: like toggles the reader's reaction, comment opens the post's comments under it.
struct PostActions: View {
  let viewModel: FeedViewModel
  let post: NeighborlyPost

  var body: some View {
    HStack(spacing: 8) {
      Button {
        viewModel.toggleLike(post)
      } label: {
        Label(
          viewModel.isLiked(post) ? FeedStrings.unlike : FeedStrings.like,
          systemImage: viewModel.isLiked(post) ? "heart.fill" : "heart"
        )
        .foregroundStyle(viewModel.isLiked(post) ? NeighborlyPalette.like : Color.primary)
        .frame(maxWidth: .infinity)
      }
      .accessibilityLabel(viewModel.isLiked(post) ? FeedStrings.unlike : FeedStrings.like)
      Button {
        Task { await viewModel.toggleThread(post) }
      } label: {
        Label(FeedStrings.comment, systemImage: "bubble.left")
          .frame(maxWidth: .infinity)
      }
      .accessibilityLabel(FeedStrings.comment)
    }
    .buttonStyle(.plain)
    .padding(.vertical, 4)
    .overlay(alignment: .top) { Rectangle().fill(NeighborlyPalette.line).frame(height: 1) }
  }
}

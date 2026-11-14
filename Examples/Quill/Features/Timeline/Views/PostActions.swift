import SwiftUIWeb

/// Reply, repost and like, each with its count. Reply opens the thread; repost and like toggle.
struct PostActions: View {
  let viewModel: TimelineViewModel
  let post: QuillPost

  var body: some View {
    HStack(spacing: 40) {
      Button { viewModel.open(post) } label: {
        HStack(spacing: 6) {
          Image(systemName: "bubble.left")
          Text(Numbers.compact(viewModel.replies(of: post)))
        }
      }
      .accessibilityLabel(TimelineStrings.reply)
      Button { viewModel.toggleRepost(post) } label: {
        HStack(spacing: 6) {
          Image(systemName: "arrow.2.squarepath")
          Text(Numbers.compact(viewModel.reposts(of: post)))
        }
        .foregroundStyle(viewModel.isReposted(post) ? QuillPalette.repost : Color.primary)
      }
      .accessibilityLabel(viewModel.isReposted(post) ? TimelineStrings.undoRepost : TimelineStrings.repost)
      Button { viewModel.toggleLike(post) } label: {
        HStack(spacing: 6) {
          Image(systemName: viewModel.isLiked(post) ? "heart.fill" : "heart")
          Text(Numbers.compact(viewModel.likes(of: post)))
        }
        .foregroundStyle(viewModel.isLiked(post) ? QuillPalette.like : Color.primary)
      }
      .accessibilityLabel(viewModel.isLiked(post) ? TimelineStrings.unlike : TimelineStrings.like)
    }
    .font(.subheadline)
    .buttonStyle(.plain)
    .padding(.top, 4)
  }
}

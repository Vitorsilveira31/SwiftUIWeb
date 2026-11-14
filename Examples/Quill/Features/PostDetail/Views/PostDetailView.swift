import SwiftUIWeb

/// A post with its replies, and the field to write one.
struct PostDetailView: View {
  @State private var viewModel: PostDetailViewModel
  let close: @MainActor @Sendable () -> Void

  init(viewModel: PostDetailViewModel, close: @escaping @MainActor @Sendable () -> Void) {
    _viewModel = State(wrappedValue: viewModel)
    self.close = close
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(PostDetailStrings.title).font(.headline)
        Spacer()
        Button(PostDetailStrings.close, action: close)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          QuillPostHeader(author: viewModel.post.author)
          Text(viewModel.post.text)
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
          Divider()
          if viewModel.state == .loaded {
            ForEach(viewModel.replies) { reply in
              ReplyRow(reply: reply)
              Divider()
            }
          } else {
            QuillStatusView(state: viewModel.state, loading: PostDetailStrings.loading, failedTitle: PostDetailStrings.failedTitle, retry: PostDetailStrings.retry) {
              Task { await viewModel.load() }
            }
          }
        }
      }
      ReplyComposer(viewModel: viewModel)
    }
    .padding(16)
    .frame(minWidth: 320, minHeight: 360)
    .task { await viewModel.load() }
  }
}

import SwiftUIWeb

/// The field to write a comment under a post, the button that sends it, and the note when that failed.
struct ThreadComposer: View {
  let viewModel: PostThreadViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        TextField(FeedStrings.commentPrompt, text: Binding(get: { viewModel.draft }, set: { viewModel.draft = $0 }))
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await viewModel.send() } }
        Button(FeedStrings.post) { Task { await viewModel.send() } }
          .buttonStyle(.bordered)
          .disabled(!viewModel.canSend || viewModel.isSending)
      }
      if viewModel.sendFailed {
        Text(FeedStrings.commentFailed).font(.caption).foregroundStyle(.red)
      }
    }
  }
}

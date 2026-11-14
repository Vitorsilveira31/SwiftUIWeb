import SwiftUIWeb

/// The box at the top of the feed: a line to write in, and the button that shares it.
struct PostComposer: View {
  let viewModel: FeedViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        TextField(FeedStrings.composerPrompt, text: Binding(get: { viewModel.draft }, set: { viewModel.draft = $0 }))
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await viewModel.publishDraft() } }
        Button(FeedStrings.post) { Task { await viewModel.publishDraft() } }
          .buttonStyle(.borderedProminent)
          .disabled(!viewModel.canPublish)
      }
      if viewModel.publishFailed {
        Text(FeedStrings.sendFailed).font(.caption).foregroundStyle(.red)
      }
    }
    .padding(12)
    .background(NeighborlyPalette.card)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

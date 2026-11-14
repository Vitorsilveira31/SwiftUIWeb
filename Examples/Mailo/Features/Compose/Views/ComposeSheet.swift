import SwiftUIWeb

/// The new message in a sheet: the fields, what went wrong, and the buttons to save a draft or send.
struct ComposeSheet: View {
  let viewModel: ComposeViewModel
  let close: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(ComposeStrings.title).font(.headline)
        Spacer()
        Button(ComposeStrings.close, action: close)
      }
      ComposeFields(viewModel: viewModel)
      if viewModel.failed {
        Text(ComposeStrings.failed).font(.caption).foregroundStyle(.red)
      }
      HStack(spacing: 8) {
        Spacer()
        Button(ComposeStrings.saveDraft) {
          viewModel.saveDraft()
          close()
        }
        .buttonStyle(.bordered)
        Button(ComposeStrings.send) {
          Task {
            if await viewModel.send() { close() }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canSend || viewModel.isSending)
      }
    }
    .padding(16)
    .frame(minWidth: 320, minHeight: 420)
  }
}

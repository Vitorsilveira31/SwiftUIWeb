import SwiftUIWeb

/// The recipient, the subject and the body of the message.
struct ComposeFields: View {
  let viewModel: ComposeViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(ComposeStrings.to).frame(width: 64, alignment: .leading)
        TextField(ComposeStrings.toPlaceholder, text: Binding(get: { viewModel.to }, set: { viewModel.to = $0 }))
          .textFieldStyle(.roundedBorder)
      }
      HStack(spacing: 8) {
        Text(ComposeStrings.subject).frame(width: 64, alignment: .leading)
        TextField(ComposeStrings.subject, text: Binding(get: { viewModel.subject }, set: { viewModel.subject = $0 }))
          .textFieldStyle(.roundedBorder)
      }
      TextEditor(text: Binding(get: { viewModel.body }, set: { viewModel.body = $0 }))
        .frame(minHeight: 220)
    }
  }
}

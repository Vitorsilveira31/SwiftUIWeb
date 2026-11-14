import SwiftUIWeb

/// The search box, on the home page and on the results: the text stays in it, and the suggestions open under it.
struct SeekrSearchBox: View {
  let shell: SeekrShellViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        TextField(SearchStrings.prompt, text: Binding(get: { shell.query }, set: { shell.edit($0) }))
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await shell.submit(shell.query) } }
        Button(SearchStrings.search) { Task { await shell.submit(shell.query) } }
          .buttonStyle(.borderedProminent)
      }
      SeekrSuggestionList(shell: shell)
    }
  }
}

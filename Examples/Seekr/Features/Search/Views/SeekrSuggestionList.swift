import SwiftUIWeb

/// The suggestions under the search box: a click searches for the suggestion.
struct SeekrSuggestionList: View {
  let shell: SeekrShellViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(shell.suggestions.suggestions, id: \.self) { suggestion in
        Button(suggestion) { Task { await shell.submit(suggestion) } }
          .buttonStyle(.plain)
          .padding(.vertical, 6)
          .padding(.horizontal, 12)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

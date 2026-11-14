import SwiftUIWeb

/// The snippet of a result, with the query's words in bold.
struct SeekrSnippet: View {
  let text: String
  let query: String

  var body: some View {
    SnippetRuns.text(text, query: query).foregroundStyle(.secondary)
  }
}

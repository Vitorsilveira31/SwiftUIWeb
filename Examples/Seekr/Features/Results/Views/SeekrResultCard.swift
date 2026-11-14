import SwiftUIWeb

/// One result: the site's address as a breadcrumb, the title as a link, and a snippet with the query's words in bold.
struct SeekrResultCard: View {
  let result: SeekrResult
  let query: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(result.site) › posts › \(result.id)").font(.caption).foregroundStyle(.secondary)
      if let destination = URL(string: result.link) {
        Link(destination: destination) {
          Text(result.title).font(.title3).foregroundStyle(SeekrPalette.indigo)
        }
      } else {
        Text(result.title).font(.title3)
      }
      SeekrSnippet(text: result.snippet, query: query)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

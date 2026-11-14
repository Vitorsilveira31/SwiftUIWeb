import SwiftUIWeb

/// Who wrote a post: their name, then their handle.
struct QuillPostHeader: View {
  let author: QuillUser

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(author.name).fontWeight(.bold).lineLimit(1)
      Text(author.handle).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

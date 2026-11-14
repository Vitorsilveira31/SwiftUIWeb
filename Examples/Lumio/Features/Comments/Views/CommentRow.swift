import SwiftUIWeb

/// One comment: who, then what they said.
struct CommentRow: View {
  let comment: LumioComment

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(comment.author).font(.subheadline).fontWeight(.semibold)
      Text(comment.text).font(.callout)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 6)
  }
}

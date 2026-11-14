import SwiftUIWeb

/// One comment under a post: who wrote it, then what they said.
struct ThreadRow: View {
  let comment: NeighborlyComment

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(comment.author).font(.subheadline).fontWeight(.semibold)
      Text(comment.text).font(.callout)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(NeighborlyPalette.canvas)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

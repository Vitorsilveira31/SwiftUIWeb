import SwiftUIWeb

/// Who posted: their picture, their name and where they are.
struct PostHeader: View {
  let author: LumioUser

  var body: some View {
    HStack(spacing: 10) {
      LumioAvatar(user: author, size: 34, ring: true)
      VStack(alignment: .leading, spacing: 0) {
        Text(author.username).font(.subheadline).fontWeight(.semibold)
        Text(author.city).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

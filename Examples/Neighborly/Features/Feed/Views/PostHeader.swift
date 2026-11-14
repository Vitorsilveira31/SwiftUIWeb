import SwiftUIWeb

/// Who wrote the post: their picture, their name and where they live. A tap opens their profile.
struct PostHeader: View {
  let author: NeighborlyUser
  let openPerson: @MainActor @Sendable (Int) -> Void

  var body: some View {
    Button {
      openPerson(author.id)
    } label: {
      HStack(spacing: 10) {
        NeighborlyAvatar(user: author, size: 40)
        VStack(alignment: .leading, spacing: 0) {
          Text(author.name).fontWeight(.semibold)
          Text(author.city).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
      }
    }
    .buttonStyle(.plain)
  }
}

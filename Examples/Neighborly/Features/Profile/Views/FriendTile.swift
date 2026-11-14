import SwiftUIWeb

/// A friend as a card: their picture and name; a tap opens their profile.
struct FriendTile: View {
  let user: NeighborlyUser
  let openPerson: @MainActor @Sendable (Int) -> Void

  var body: some View {
    Button {
      openPerson(user.id)
    } label: {
      HStack(spacing: 12) {
        NeighborlyAvatar(user: user, size: 44)
        VStack(alignment: .leading, spacing: 0) {
          Text(user.name).fontWeight(.semibold).lineLimit(1)
          Text(user.city).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(NeighborlyPalette.card)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}

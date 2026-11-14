import SwiftUIWeb

/// The friends of the person, as a grid of names with their pictures.
struct ProfileFriends: View {
  let friends: [NeighborlyUser]
  let openPerson: @MainActor @Sendable (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(ProfileStrings.friendsTitle).font(.headline)
      if friends.isEmpty {
        Text(ProfileStrings.noFriends).foregroundStyle(.secondary)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
          ForEach(friends) { friend in
            FriendTile(user: friend, openPerson: openPerson)
          }
        }
      }
    }
    .padding(.horizontal, 16)
  }
}

import SwiftUIWeb

/// A person in the contacts column: their picture and name, and a tap that opens their profile.
struct ContactRow: View {
  let user: NeighborlyUser
  let openPerson: @MainActor @Sendable (Int) -> Void

  var body: some View {
    Button {
      openPerson(user.id)
    } label: {
      HStack(spacing: 10) {
        NeighborlyAvatar(user: user, size: 32)
        Text(user.name).lineLimit(1)
        Spacer()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
  }
}

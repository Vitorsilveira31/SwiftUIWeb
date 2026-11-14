import SwiftUIWeb

/// The people to see the albums of, side by side; the one picked has the ring.
struct PeoplePicker: View {
  let people: [NeighborlyUser]
  let selectedID: Int
  let select: @MainActor @Sendable (Int) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(people) { person in
          Button {
            select(person.id)
          } label: {
            VStack(spacing: 4) {
              NeighborlyAvatar(user: person, size: 48, ring: person.id == selectedID)
              Text(person.username).font(.caption).lineLimit(1).frame(width: 76)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(PhotosStrings.albumsOf(person.name))
        }
      }
      .padding(.horizontal, 4)
    }
  }
}

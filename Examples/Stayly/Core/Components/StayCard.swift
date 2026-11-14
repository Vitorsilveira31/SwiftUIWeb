import SwiftUIWeb

/// A stay in a list: the whole card opens the stay, and the heart saves it. The heart is a sibling of the card's button, not inside it.
struct StayCard: View {
  let stay: Stay
  var nights: Int?
  let isFavorite: Bool
  let open: @MainActor @Sendable () -> Void
  let toggleFavorite: @MainActor @Sendable () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Button(action: open) {
        StayCardBody(stay: stay, nights: nights)
      }
      .buttonStyle(.plain)
      StayFavoriteButton(isFavorite: isFavorite, toggle: toggleFavorite)
        .padding(12)
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: StaylyLayout.cardRadius))
    .overlay { RoundedRectangle(cornerRadius: StaylyLayout.cardRadius).stroke(Color.gray, lineWidth: 1) }
  }
}

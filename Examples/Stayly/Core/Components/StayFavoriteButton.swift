import SwiftUIWeb

/// The heart that saves a stay to the reader's list (for this session).
struct StayFavoriteButton: View {
  let isFavorite: Bool
  let toggle: @MainActor @Sendable () -> Void

  var body: some View {
    Button(action: toggle) {
      Image(systemName: isFavorite ? "heart.fill" : "heart")
        .foregroundStyle(isFavorite ? StaylyPalette.coral : Color.white)
        .font(.title3)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isFavorite ? StayCopy.unsave : StayCopy.save)
  }
}

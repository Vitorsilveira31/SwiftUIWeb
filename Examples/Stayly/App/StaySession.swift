import SwiftUIWeb

/// What the reader does in this session: the stays they saved with a heart, and the reservations they made. Nothing is kept after the page closes.
@MainActor @Observable
final class StaySession {
  private(set) var favoriteIDs: Set<Int> = []
  /// The newest first.
  private(set) var reservations: [StayReservation] = []

  func isFavorite(_ stay: Stay) -> Bool { favoriteIDs.contains(stay.id) }

  func toggleFavorite(_ stay: Stay) {
    if favoriteIDs.contains(stay.id) { favoriteIDs.remove(stay.id) } else { favoriteIDs.insert(stay.id) }
  }

  func record(_ reservation: StayReservation) {
    reservations.insert(reservation, at: 0)
  }
}

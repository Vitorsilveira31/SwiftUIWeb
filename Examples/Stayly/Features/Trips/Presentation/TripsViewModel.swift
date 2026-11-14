import SwiftUIWeb

/// The trips: the reservations the session made, newest first.
@MainActor @Observable
final class TripsViewModel {
  private let session: StaySession

  init(session: StaySession) { self.session = session }

  var reservations: [StayReservation] { session.reservations }
}

import SwiftUIWeb

/// Where a reservation is recorded.
protocol ReservationsRepository: Sendable {
  func reserve(stay: Stay, checkIn: Date, checkOut: Date, guests: Int) async throws -> StayReservation
}

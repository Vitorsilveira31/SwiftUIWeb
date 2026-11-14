import SwiftUIWeb

protocol ReserveStayUseCase: Sendable {
  func execute(stay: Stay, checkIn: Date, checkOut: Date, guests: Int) async throws -> StayReservation
}

struct DefaultReserveStayUseCase: ReserveStayUseCase {
  let repository: any ReservationsRepository

  func execute(stay: Stay, checkIn: Date, checkOut: Date, guests: Int) async throws -> StayReservation {
    try await repository.reserve(stay: stay, checkIn: checkIn, checkOut: checkOut, guests: guests)
  }
}

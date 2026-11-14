import SwiftUIWeb
import CloneKit

/// A reservation is a to-do for the host, posted to the API. The service answers with its id; the reader's details stay in this session.
struct LiveReservationsRepository: ReservationsRepository {
  let client: PlaceholderClient

  func reserve(stay: Stay, checkIn: Date, checkOut: Date, guests: Int) async throws -> StayReservation {
    let nights = StayDays.nights(from: checkIn, to: checkOut)
    let created = try await client.addTodo(userId: stay.hostID, title: "\(stay.title): \(nights) nights for \(guests) guests", completed: false)
    return StayReservation(id: created.id, stay: stay, checkIn: checkIn, checkOut: checkOut, guests: guests)
  }
}

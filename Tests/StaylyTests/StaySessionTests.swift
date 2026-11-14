import Testing
@testable import Stayly

@MainActor
struct StaySessionTests {
  @Test func aHeartTogglesASavedStay() {
    let session = StaySession()
    let saved = stay(4)
    #expect(!session.isFavorite(saved))
    session.toggleFavorite(saved)
    #expect(session.isFavorite(saved))
    session.toggleFavorite(saved)
    #expect(!session.isFavorite(saved))
  }

  @Test func theNewestReservationIsFirst() {
    let session = StaySession()
    let first = StayReservation(id: 1, stay: stay(1), checkIn: StayDays.date(day: startDay), checkOut: StayDays.date(day: startDay + 1), guests: 1)
    let second = StayReservation(id: 2, stay: stay(2), checkIn: StayDays.date(day: startDay), checkOut: StayDays.date(day: startDay + 2), guests: 2)
    session.record(first)
    session.record(second)
    #expect(session.reservations.map(\.id) == [2, 1])
    #expect(second.total == 2 * second.stay.pricePerNight)
  }
}

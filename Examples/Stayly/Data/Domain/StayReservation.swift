import SwiftUIWeb

/// A reservation made in this session: the stay, the dates and the guests. Its total is the nights times the price per night.
struct StayReservation: Identifiable, Hashable {
  let id: Int
  let stay: Stay
  let checkIn: Date
  let checkOut: Date
  let guests: Int

  var nights: Int { StayDays.nights(from: checkIn, to: checkOut) }

  /// Nil when the total overflows an Int.
  var total: Int? { StayTerms.total(perNight: stay.pricePerNight, nights: nights) }
}

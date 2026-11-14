import SwiftUIWeb

/// What the reader is looking for: a city (empty for anywhere), the dates and how many guests.
struct StaySearch: Hashable {
  var destination: String
  var checkIn: Date
  var checkOut: Date
  var guests: Int

  var nights: Int { StayDays.nights(from: checkIn, to: checkOut) }

  /// Where a search starts: anywhere, two nights from today, two guests.
  static func starting(on today: Date) -> StaySearch {
    let day = StayDays.number(today)
    return StaySearch(destination: "", checkIn: StayDays.date(day: day), checkOut: StayDays.date(day: day + 2), guests: 2)
  }
}

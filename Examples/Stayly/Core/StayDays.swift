import SwiftUIWeb

/// Dates as day numbers, without Foundation's `Calendar` (Embedded Swift has none). A day is the number of days since 1970-01-01, read
/// from the instant at noon, so a time zone's offset (under twelve hours) does not move a date onto another day.
enum StayDays {
  static func number(_ date: Date) -> Int {
    Int(((date.timeIntervalSince1970 + 43_200) / 86_400).rounded(.down))
  }

  /// The midnight (UTC) that starts `day`.
  static func date(day: Int) -> Date { Date(timeIntervalSince1970: Double(day) * 86_400) }

  /// The nights from one date to another: at least one, whatever the order, so a stay is never free or negative.
  static func nights(from checkIn: Date, to checkOut: Date) -> Int { max(1, number(checkOut) - number(checkIn)) }

  /// The year, month and day of a date (the days-from-civil algorithm, by Howard Hinnant).
  static func civil(_ date: Date) -> (year: Int, month: Int, day: Int) {
    let z = number(date) + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthIndex = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
    let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (year, month, day)
  }
}

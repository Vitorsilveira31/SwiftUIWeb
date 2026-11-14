import Foundation
import SwiftUIWebCore
import Testing

/// The Embedded Core calendar and time-zone fallbacks must return a value or nil for every input; a trap aborts the process,
/// so each lead below is a separate test that must run alone when it is checked.
@Suite struct FoundationFallbacksTests {
  private let gregorian = Calendar(identifier: .gregorian)

  @Test func calendarComponentsOfSaneDatesAreUnchanged() {
    // 2000-02-29T12:34:56Z is a Tuesday; the Unix epoch is a Thursday; one second before it is a Wednesday.
    let leapDay = gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: Date(timeIntervalSince1970: 951_827_696))
    #expect(leapDay.year == 2000)
    #expect(leapDay.month == 2)
    #expect(leapDay.day == 29)
    #expect(leapDay.hour == 12)
    #expect(leapDay.minute == 34)
    #expect(leapDay.second == 56)
    #expect(leapDay.weekday == 3)
    let epoch = gregorian.dateComponents([.year, .month, .day, .weekday], from: Date(timeIntervalSince1970: 0))
    #expect(epoch.year == 1970)
    #expect(epoch.month == 1)
    #expect(epoch.day == 1)
    #expect(epoch.weekday == 5)
    let beforeEpoch = gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: Date(timeIntervalSince1970: -1))
    #expect(beforeEpoch.year == 1969)
    #expect(beforeEpoch.month == 12)
    #expect(beforeEpoch.day == 31)
    #expect(beforeEpoch.hour == 23)
    #expect(beforeEpoch.minute == 59)
    #expect(beforeEpoch.second == 59)
    #expect(beforeEpoch.weekday == 4)
  }

  /// Seconds beyond the Int64 day range (and non-finite seconds) trapped in `Int64((seconds / 86_400).rounded(.down))`.
  @Test func calendarComponentsOfDatesOutsideTheDayRangeDoNotTrap() {
    let extreme: [Double] = [1e300, -1e300, .infinity, -.infinity, .nan, Double(Int64.max), -Double(Int64.max)]
    for seconds in extreme {
      let components = gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday, .quarter], from: Date(timeIntervalSince1970: seconds))
      #expect(components.day.map { (1...31).contains($0) } == true, "\(seconds)")
    }
  }

  /// `dateComponents(_:from:to:)` converted whole days with `Int(days)`, which traps when the span does not fit in Int.
  @Test func componentsBetweenDistantDatesDoNotTrap() {
    let span = gregorian.dateComponents([.day, .hour, .minute, .second], from: Date(timeIntervalSince1970: -1e300), to: Date(timeIntervalSince1970: 1e300))
    #expect(span.day != nil)
    #expect(span.hour != nil)
    #expect(span.minute != nil)
    #expect(span.second != nil)
  }

  @Test func componentsBetweenNearbyDatesAreUnchanged() {
    let forward = gregorian.dateComponents([.day, .hour, .minute, .second], from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 90_061))
    #expect(forward.day == 1)
    #expect(forward.hour == 1)
    #expect(forward.minute == 1)
    #expect(forward.second == 1)
    let backward = gregorian.dateComponents([.day, .hour, .minute, .second], from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: -90_061))
    #expect(backward.day == -1)
    #expect(backward.hour == -1)
    #expect(backward.minute == -1)
    #expect(backward.second == -1)
  }

  /// A GMT/UTC prefix with an empty offset indexed `parts[0]` of an empty split result and trapped instead of returning nil.
  // A fixed UTC-3 zone (no daylight saving), as the Calendar demo's browser zone is. 2026-11-11T00:00Z is 1_794_355_200.

  @Test func startOfDayInANonUTCZoneIsMidnightThere() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3_600)!
    let tenInTheMorning = Date(timeIntervalSince1970: 1_794_355_200 + 13 * 3_600)  // 10:00 in UTC-3
    let start = calendar.startOfDay(for: tenInTheMorning)
    #expect(start.timeIntervalSince1970 == 1_794_366_000)  // 2026-11-11T03:00Z, midnight in UTC-3
    let parts = calendar.dateComponents([.year, .month, .day, .hour], from: start)
    #expect(parts.year == 2026 && parts.month == 11 && parts.day == 11 && parts.hour == 0)
  }

  @Test func monthStartAndDateFromComponentsUseTheCalendarZone() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3_600)!
    let firstOfMonth = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))
    #expect(firstOfMonth?.timeIntervalSince1970 == 1_793_502_000)  // 2026-11-01T03:00Z
    let afternoon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 16, minute: 0))
    #expect(afternoon?.timeIntervalSince1970 == 1_794_423_600)  // 2026-11-11T19:00Z
    let back = afternoon.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
    #expect(back?.day == 11 && back?.hour == 16 && back?.minute == 0)
  }

  @Test func addingDaysKeepsTheWallClockInTheCalendarZone() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3_600)!
    let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 9))!
    let later = calendar.date(byAdding: .day, value: 20, to: start)!
    let parts = calendar.dateComponents([.year, .month, .day, .hour], from: later)
    #expect(parts.year == 2026 && parts.month == 12 && parts.day == 1 && parts.hour == 9)
  }

  @Test func zoneNameAndWeekComeFromTheBrowserHostAndDefaultWithout() {
    // The defaults first, then a fake host (Lisbon, Monday-first weeks, Sunday-first for en-US), restored afterwards.
    #expect(TimeZone.current.identifier == "GMT")
    #expect(Calendar.current.firstWeekday == 1)
    #expect(Calendar.current.minimumDaysInFirstWeek == 1)
    defer {
      _LocalTimeZoneHost.install(nil)
      _LocalTimeZoneHost.installZoneAndWeek(identifier: nil, week: nil)
    }
    _LocalTimeZoneHost.install { _ in 0 }
    _LocalTimeZoneHost.installZoneAndWeek(
      identifier: { "Europe/Lisbon" },
      week: { tag in tag == "en-US" ? (firstWeekday: 1, minimumDays: 1) : (firstWeekday: 2, minimumDays: 4) }
    )
    #expect(TimeZone.current.identifier == "Europe/Lisbon")
    #expect(Calendar.current.firstWeekday == 2)
    #expect(Calendar.current.minimumDaysInFirstWeek == 4)
    #expect(Calendar(identifier: .gregorian).firstWeekday == 2)
    // A calendar whose locale is set takes that locale's week.
    var american = Calendar(identifier: .gregorian)
    american.locale = Locale(identifier: "en-US")
    #expect(american.firstWeekday == 1 && american.minimumDaysInFirstWeek == 1)
  }

  @Test func currentTimeZoneWithoutABrowserHostIsUTC() {
    // Native and Embedded tests install no host, so the local zone is the UTC fallback.
    #expect(TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: 1_794_355_200)) == 0)
    #expect(Calendar.current.timeZone.secondsFromGMT() == 0)
  }

  @Test func timeZoneWithEmptyOffsetReturnsNil() {
    for identifier in ["GMT+", "GMT-", "GMT:", "UTC+", "UTC-", "GMT+:"] {
      #expect(TimeZone(identifier: identifier) == nil, "\(identifier)")
    }
  }

  /// Hours were bounded above only, so a very negative value overflowed `hours * 3_600` and trapped.
  @Test func timeZoneWithOutOfRangeOffsetReturnsNil() {
    for identifier in ["GMT+-9223372036854775808", "GMT+-5", "GMT+24", "GMT+99:00", "GMT+9223372036854775807", "GMT+5:60", "GMT+5:-1", "GMT+x"] {
      #expect(TimeZone(identifier: identifier) == nil, "\(identifier)")
    }
  }

  @Test func timeZoneValidOffsetsStillParse() {
    #expect(TimeZone(identifier: "GMT+5")?.secondsFromGMT() == 5 * 3_600)
    #expect(TimeZone(identifier: "GMT-05:30")?.secondsFromGMT() == -19_800)
    #expect(TimeZone(identifier: "UTC+14")?.secondsFromGMT() == 14 * 3_600)
    #expect(TimeZone(identifier: "gmt+23:59")?.secondsFromGMT() == 86_340)
    #expect(TimeZone(identifier: "GMT-0")?.secondsFromGMT() == 0)
    #expect(TimeZone(identifier: "GMT")?.secondsFromGMT() == 0)
    #expect(TimeZone(identifier: "Europe/Paris") == nil)
  }
}

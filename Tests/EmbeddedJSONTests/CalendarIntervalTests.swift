import Foundation
import SwiftUIWebCore
import Testing

/// The Calendar members and DateInterval that calendar layouts use, checked with fixed dates in UTC and in a zone west of
/// Greenwich. The browser's time zones have fixed offsets (no daylight-saving rules), so the second zone is UTC-5.
@Suite struct CalendarIntervalTests {
  /// 2000-02-29T00:00:00Z, a day of a leap year.
  private let leapDayMidnight: Double = 951_782_400
  /// A calendar in UTC explicitly: a default one follows the local zone, which other tests may install a host for.
  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private var eastern: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: -5 * 3_600)!
    return calendar
  }

  @Test func sameDayFollowsTheCalendarsTimeZone() {
    let early = Date(timeIntervalSince1970: leapDayMidnight + 1_800)
    let late = Date(timeIntervalSince1970: leapDayMidnight + 86_340)
    let nextDay = Date(timeIntervalSince1970: leapDayMidnight + 86_400)
    #expect(utc.isDate(early, inSameDayAs: late))
    #expect(!utc.isDate(late, inSameDayAs: nextDay))

    // 03:00 UTC and 04:30 UTC are 22:00 and 23:30 on 2000-02-28 in UTC-5; 05:00 UTC is midnight of 02-29 there.
    let twentyTwo = Date(timeIntervalSince1970: leapDayMidnight + 10_800)
    let twentyThreeThirty = Date(timeIntervalSince1970: leapDayMidnight + 16_200)
    let midnight = Date(timeIntervalSince1970: leapDayMidnight + 18_000)
    #expect(eastern.isDate(twentyTwo, inSameDayAs: twentyThreeThirty))
    #expect(!eastern.isDate(twentyThreeThirty, inSameDayAs: midnight))
    #expect(utc.isDate(twentyTwo, inSameDayAs: midnight))
  }

  @Test func equalityToAMonthOrAnHourIgnoresTheSmallerFields() {
    let first = Date(timeIntervalSince1970: 949_363_200)
    let last = Date(timeIntervalSince1970: leapDayMidnight + 43_200)
    let march = Date(timeIntervalSince1970: 951_868_800)
    #expect(utc.isDate(first, equalTo: last, toGranularity: .month))
    #expect(!utc.isDate(first, equalTo: march, toGranularity: .month))
    #expect(utc.isDate(first, equalTo: march, toGranularity: .year))
    #expect(!utc.isDate(last, equalTo: Date(timeIntervalSince1970: leapDayMidnight + 46_800), toGranularity: .hour))
    #expect(utc.isDate(last, equalTo: Date(timeIntervalSince1970: leapDayMidnight + 43_300), toGranularity: .hour))
  }

  @Test func dateIntervalOfAMonthDayAndWeek() {
    let noon = Date(timeIntervalSince1970: leapDayMidnight + 43_200)

    let month = utc.dateInterval(of: .month, for: noon)
    #expect(month?.start == Date(timeIntervalSince1970: 949_363_200))
    #expect(month?.end == Date(timeIntervalSince1970: 951_868_800))
    #expect(month?.duration == 2_505_600)
    #expect(month?.contains(noon) == true)

    let day = utc.dateInterval(of: .day, for: noon)
    #expect(day?.start == Date(timeIntervalSince1970: leapDayMidnight))
    #expect(day?.duration == 86_400)

    // 2000-02-29 is a Tuesday; with Sunday as the first weekday its week began on Sunday the 27th.
    let week = utc.dateInterval(of: .weekOfYear, for: noon)
    #expect(week?.start == Date(timeIntervalSince1970: leapDayMidnight - 172_800))
    #expect(week?.duration == 604_800)

    // A week that starts on Monday: the Tuesday is one day after the week's start.
    var monday = utc
    monday.firstWeekday = 2
    #expect(monday.dateInterval(of: .weekOfYear, for: noon)?.start == Date(timeIntervalSince1970: leapDayMidnight - 86_400))
  }

  @Test func rangesOfDaysMonthsAndHours() {
    let noon = Date(timeIntervalSince1970: leapDayMidnight + 43_200)
    #expect(utc.range(of: .day, in: .month, for: noon) == (1 ..< 30))
    #expect(utc.range(of: .day, in: .month, for: Date(timeIntervalSince1970: 946_684_800)) == (1 ..< 32))
    #expect(utc.range(of: .day, in: .year, for: noon) == (1 ..< 367))
    #expect(utc.range(of: .month, in: .year, for: noon) == (1 ..< 13))
    #expect(utc.range(of: .hour, in: .day, for: noon) == (0 ..< 24))
    #expect(utc.range(of: .day, in: .weekOfMonth, for: noon) == nil)
  }

  @Test func settingTheTimeOfDayKeepsTheDayInTheCalendarsZone() {
    let noon = Date(timeIntervalSince1970: leapDayMidnight + 43_200)
    #expect(utc.date(bySettingHour: 9, minute: 0, second: 0, of: noon) == Date(timeIntervalSince1970: leapDayMidnight + 32_400))
    // Noon UTC is 07:00 on the same day in UTC-5, and 09:00 there is 14:00 UTC.
    #expect(eastern.date(bySettingHour: 9, minute: 0, second: 0, of: noon) == Date(timeIntervalSince1970: leapDayMidnight + 50_400))
    #expect(utc.date(bySettingHour: 24, minute: 0, second: 0, of: noon) == nil)
  }

  @Test func dateByAddingDaysIsOptionalAndCompactMapsOverIt() {
    let start = Date(timeIntervalSince1970: leapDayMidnight)
    let days = (0 ..< 3).compactMap { index -> Date? in
      guard let date = utc.date(byAdding: .day, value: index, to: start) else { return nil }
      return date
    }
    #expect(days == [
      Date(timeIntervalSince1970: leapDayMidnight),
      Date(timeIntervalSince1970: leapDayMidnight + 86_400),
      Date(timeIntervalSince1970: leapDayMidnight + 172_800),
    ])
  }

  @Test func standaloneSymbolArraysMatchTheContextualOnes() {
    #expect(utc.standaloneWeekdaySymbols.count == 7)
    #expect(utc.standaloneWeekdaySymbols == utc.weekdaySymbols)
    #expect(utc.shortStandaloneWeekdaySymbols == utc.shortWeekdaySymbols)
    #expect(utc.veryShortStandaloneWeekdaySymbols == utc.veryShortWeekdaySymbols)
    #expect(utc.standaloneMonthSymbols.count == 12)
    #expect(utc.standaloneMonthSymbols == utc.monthSymbols)
    #expect(utc.shortStandaloneMonthSymbols == utc.shortMonthSymbols)
    #expect(utc.veryShortStandaloneMonthSymbols == utc.veryShortMonthSymbols)
  }

  /// A day of the year 2026 in UTC (2026-01-01 was a Thursday).
  private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
  }

  @Test func weekFieldsFollowTheCalendarsFirstWeekdayAndMinimumDays() {
    var iso = utc
    iso.firstWeekday = 2
    iso.minimumDaysInFirstWeek = 4
    func fields(_ date: Date) -> [Int] {
      let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
      return [c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0]
    }
    #expect(fields(day(2026, 1, 1)) == [2026, 1])
    #expect(fields(day(2025, 12, 29)) == [2026, 1], "the Monday before the first Thursday starts week 1 of 2026")
    #expect(fields(day(2027, 1, 1)) == [2026, 53], "the first days of 2027 are the last week of 2026")
    #expect(fields(day(2026, 6, 15)) == [2026, 25])

    var us = utc
    us.firstWeekday = 1
    us.minimumDaysInFirstWeek = 1
    let june = us.dateComponents([.weekOfYear, .weekOfMonth], from: day(2026, 6, 15))
    #expect(june.weekOfYear == 25)
    #expect(june.weekOfMonth == 3)
    #expect(us.component(.weekOfMonth, from: day(2026, 5, 30)) == 5)
    #expect(us.component(.weekdayOrdinal, from: day(2026, 6, 15)) == 3)
  }

  @Test func buildingADateInAFixedOffsetZoneKeepsItsWallReading() {
    // date(from:) resolves through the same function as the daylight-saving cases below; a fixed zone checks the ordinary path.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: -5 * 3_600)!
    let parts = DateComponents(year: 2026, month: 3, day: 8, hour: 2, minute: 30)
    #expect(calendar.date(from: parts).map { Int($0.timeIntervalSince1970) } == 1_772_953_200 + 1_800, "02:30 at UTC-5 is 07:30 UTC")
  }

  @Test func addingADayResolvesAWallTimeThatTheClocksSkipped() {
    // Adding a day to March 7 02:30 in New York lands on March 8 02:30, which does not exist: it becomes 03:30 EDT (07:30 UTC),
    // not 01:30 EST, which the offset difference of the two instants gave.
    let wall = utc.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 2, minute: 30))!
    let skipped = _instantOfWallTime(wall, offsetAt: { Date -> Int in newYork(Date) }, gap: .nextPreservingSmallerComponents, repeated: .first)
    #expect(skipped.map { Int($0.timeIntervalSince1970) } == 1_772_953_200 + 1_800)
    // An ordinary day keeps its wall reading: noon on March 9 is noon EDT.
    let noon = utc.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
    let ordinary = _instantOfWallTime(noon, offsetAt: { Date -> Int in newYork(Date) }, gap: .nextPreservingSmallerComponents, repeated: .first)
    #expect(ordinary.map { Int($0.timeIntervalSince1970) } == Int(noon.timeIntervalSince1970) + 4 * 3_600)
    // A day added across the November change: 01:30 on November 1 is the first occurrence.
    let repeated = utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))!
    let first = _instantOfWallTime(repeated, offsetAt: { Date -> Int in newYork(Date) }, gap: .nextPreservingSmallerComponents, repeated: .first)
    #expect(first.map { Int($0.timeIntervalSince1970) } == 1_793_512_800 - 1_800)
  }

  @Test func addingMonthsAndYearsClampsTheDayToTheNewMonth() {
    let january31 = utc.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))!
    #expect(utc.date(byAdding: .month, value: 1, to: january31) == utc.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 12)))
    #expect(utc.date(byAdding: .month, value: 2, to: january31) == utc.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12)))
    let leapDay = utc.date(from: DateComponents(year: 2028, month: 2, day: 29, hour: 12))!
    #expect(utc.date(byAdding: .year, value: 1, to: leapDay) == utc.date(from: DateComponents(year: 2029, month: 2, day: 28, hour: 12)))
    #expect(utc.date(byAdding: .year, value: 4, to: leapDay) == utc.date(from: DateComponents(year: 2032, month: 2, day: 29, hour: 12)))
  }

  @Test func differenceInDaysCountsCalendarDaysThenTheRest() {
    let start = utc.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9))!
    let end = utc.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 12))!
    let difference = utc.dateComponents([.day, .hour], from: start, to: end)
    #expect(difference.day == 2 && difference.hour == 3)
    let backwards = utc.dateComponents([.day, .hour], from: end, to: start)
    #expect(backwards.day == -2 && backwards.hour == -3)
  }

  @Test func addingNoDaysKeepsTheInstant() {
    let calendar = Calendar(identifier: .gregorian)
    let instant = Date(timeIntervalSince1970: 1_793_512_800 + 1_800)
    #expect(calendar.date(byAdding: .day, value: 0, to: instant) == instant)
  }

  @Test func clockUnitsAreBoundedFromTheInstantInARepeatedHour() {
    // November 1, 2026 in New York: 06:30 UTC is the second 01:30 (EST), after the clocks went back at 06:00 UTC.
    let secondOccurrence = Date(timeIntervalSince1970: 1_793_512_800 + 1_800)
    let hour = Calendar._startOfClockUnit(containing: secondOccurrence, unit: 3_600, offset: -5 * 3_600)
    #expect(hour.timeIntervalSince1970 == 1_793_512_800, "the hour starts at 06:00 UTC, inside the instant's own occurrence")
    let minute = Calendar._startOfClockUnit(containing: secondOccurrence.addingTimeInterval(95), unit: 60, offset: -5 * 3_600)
    #expect(minute.timeIntervalSince1970 == 1_793_512_800 + 1_800 + 60)
    // The first occurrence, 05:30 UTC (EDT), is in the hour that starts at 05:00 UTC.
    let firstOccurrence = Date(timeIntervalSince1970: 1_793_512_800 - 1_800)
    #expect(Calendar._startOfClockUnit(containing: firstOccurrence, unit: 3_600, offset: -4 * 3_600).timeIntervalSince1970 == 1_793_512_800 - 3_600)
    #expect(utc.dateInterval(of: .hour, for: day(2026, 6, 15))?.start == utc.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12)))
    // The two occurrences of 01:30 have the same fields and different hours: their starts differ.
    #expect(Calendar._startOfClockUnit(containing: firstOccurrence, unit: 3_600, offset: -4 * 3_600)
      != Calendar._startOfClockUnit(containing: secondOccurrence, unit: 3_600, offset: -5 * 3_600))
    #expect(utc.isDate(day(2026, 6, 15), equalTo: day(2026, 6, 15).addingTimeInterval(600), toGranularity: .hour))
    #expect(!utc.isDate(day(2026, 6, 15), equalTo: day(2026, 6, 15).addingTimeInterval(3_600), toGranularity: .hour))
    #expect(utc.isDate(day(2026, 6, 15), equalTo: day(2026, 6, 15).addingTimeInterval(30), toGranularity: .minute))
  }

  @Test func weekBasedYearGranularityComparesOnlyTheYear() {
    var us = utc
    us.firstWeekday = 1
    us.minimumDaysInFirstWeek = 1
    #expect(us.isDate(day(2026, 1, 5), equalTo: day(2026, 6, 15), toGranularity: .yearForWeekOfYear))
    #expect(!us.isDate(day(2026, 1, 5), equalTo: day(2027, 6, 15), toGranularity: .yearForWeekOfYear))
  }

  /// New York in 2026: clocks go forward at 07:00 UTC on March 8 and back at 06:00 UTC on November 1.
  private func newYork(_ instant: Date) -> Int {
    let seconds = instant.timeIntervalSince1970
    return seconds >= 1_772_953_200 && seconds < 1_793_512_800 ? -4 * 3_600 : -5 * 3_600
  }

  @Test func wallTimesResolveByThePoliciesOfAZoneWithDaylightSaving() {
    func resolve(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ matching: Calendar.MatchingPolicy = .nextTime, _ repeated: Calendar.RepeatedTimePolicy = .first) -> Int? {
      let wall = utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
      return Calendar._instant(ofWallTime: wall, offsetAt: newYork, matchingPolicy: matching, repeatedTimePolicy: repeated).map { Int($0.timeIntervalSince1970) }
    }
    // 02:30 on March 8 does not exist: the clocks jump from 02:00 EST to 03:00 EDT (07:00 UTC).
    #expect(resolve(3, 8, 2, 30, .nextTime) == 1_772_953_200, "the next valid time is the end of the skipped hour")
    #expect(resolve(3, 8, 2, 30, .nextTimePreservingSmallerComponents) == 1_772_953_200 + 1_800, "03:30 EDT")
    #expect(resolve(3, 8, 2, 30, .previousTimePreservingSmallerComponents) == 1_772_953_200 - 1_800, "01:30 EST")
    #expect(resolve(3, 8, 2, 30, .strict) == nil)
    #expect(resolve(3, 8, 3, 30, .strict) == 1_772_953_200 + 1_800, "a time that exists is not touched")
    #expect(resolve(3, 8, 1, 30, .strict) == 1_772_953_200 - 1_800)
    // 01:30 on November 1 happens twice: at 05:30 UTC (EDT) and at 06:30 UTC (EST).
    #expect(resolve(11, 1, 1, 30, .nextTime, .first) == 1_793_512_800 - 1_800)
    #expect(resolve(11, 1, 1, 30, .nextTime, .last) == 1_793_512_800 + 1_800)
    #expect(resolve(6, 15, 12, 0) == 1781539200, "an ordinary wall time takes the zone's offset")
  }

  @Test func settingATimeSearchesDaysInTheDirectionAndSkipsGapsAsFoundationDoes() {
    // The values are Apple Foundation's, read with America/New_York in 2026 (see `newYork`).
    func set(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ matching: Calendar.MatchingPolicy, _ direction: Calendar.SearchDirection) -> Int? {
      let wallDay = utc.date(from: DateComponents(year: 2026, month: month, day: day))!
      return Calendar._instant(
        settingTimeOfDay: hour * 3_600 + minute * 60, onWallDay: wallDay, offsetAt: newYork,
        matchingPolicy: matching, repeatedTimePolicy: .first, direction: direction
      ).map { Int($0.timeIntervalSince1970) }
    }
    let springForward = 1_772_953_200
    let march7At0230 = springForward - 86_400 + 1_800
    // 02:30 on March 8 was skipped. Forward, `.strict` takes the next day that has it; the other policies take 03:00.
    #expect(set(3, 8, 2, 30, .strict, .forward) == springForward + 86_400 - 1_800, "March 9 at 02:30 EDT")
    for policy in [Calendar.MatchingPolicy.nextTime, .nextTimePreservingSmallerComponents, .previousTimePreservingSmallerComponents] {
      #expect(set(3, 8, 2, 30, policy, .forward) == springForward)
      #expect(set(3, 8, 2, 30, policy, .backward) == march7At0230, "backward starts on the day before")
    }
    #expect(set(3, 8, 2, 30, .strict, .backward) == march7At0230)
    // From March 9 backward the search lands on the skipped time, and the policy resolves it.
    #expect(set(3, 9, 2, 30, .strict, .backward) == march7At0230)
    #expect(set(3, 9, 2, 30, .nextTime, .backward) == springForward)
    #expect(set(3, 9, 2, 30, .nextTimePreservingSmallerComponents, .backward) == springForward + 1_800)
    #expect(set(3, 9, 2, 30, .previousTimePreservingSmallerComponents, .backward) == springForward - 1_800)
    #expect(set(3, 9, 2, 30, .strict, .forward) == springForward + 86_400 - 1_800)
    // A time that exists is the day's, or the day before's searching backward.
    #expect(set(3, 8, 5, 0, .strict, .forward) == springForward + 2 * 3_600, "05:00 EDT is 09:00 UTC")
    #expect(set(3, 8, 5, 0, .nextTime, .backward) == springForward - 86_400 + 3 * 3_600, "March 7 at 05:00 EST")
    // 01:30 on November 1 happens twice: the first occurrence, or October 31 backward.
    #expect(set(11, 1, 1, 30, .strict, .forward) == 1_793_512_800 - 1_800)
    #expect(set(11, 1, 1, 30, .nextTime, .backward) == 1_793_512_800 - 1_800 - 86_400)
  }

  @Test func weekGranularityComparesTheWeekNotJustTheYear() {
    var us = utc
    us.firstWeekday = 1
    us.minimumDaysInFirstWeek = 1
    #expect(!us.isDate(day(2026, 1, 5), equalTo: day(2026, 6, 15), toGranularity: .weekOfYear))
    #expect(us.isDate(day(2026, 6, 14), equalTo: day(2026, 6, 20), toGranularity: .weekOfYear))
    #expect(!us.isDate(day(2026, 6, 20), equalTo: day(2026, 6, 21), toGranularity: .weekOfYear), "a new week starts on Sunday")
    #expect(us.isDate(day(2026, 6, 15), equalTo: day(2026, 6, 17), toGranularity: .weekOfMonth))
    #expect(!us.isDate(day(2026, 6, 15), equalTo: day(2026, 6, 22), toGranularity: .weekOfMonth))
    #expect(!us.isDate(day(2026, 5, 15), equalTo: day(2026, 6, 15), toGranularity: .weekOfMonth))
  }

  @Test func dateIntervalInitialisersContainmentAndOrder() {
    let start = Date(timeIntervalSince1970: 100)
    let end = Date(timeIntervalSince1970: 160)
    let fromEnds = DateInterval(start: start, end: end)
    #expect(fromEnds.duration == 60)
    #expect(DateInterval(start: start, duration: 60).end == end)
    #expect(DateInterval(start: start, duration: 60) == fromEnds)
    #expect(fromEnds.contains(start))
    #expect(fromEnds.contains(end), "the interval is closed: it holds its end")
    #expect(!fromEnds.contains(Date(timeIntervalSince1970: 161)))
    #expect(DateInterval(start: start, duration: 0).contains(start), "an interval of no duration holds its start")
    #expect(DateInterval(start: start, duration: 30) < fromEnds)
    #expect(DateInterval(start: Date(timeIntervalSince1970: 99), duration: 500) < fromEnds)
    #expect(fromEnds.compare(DateInterval(start: start, duration: 60)) == .orderedSame)
  }
}

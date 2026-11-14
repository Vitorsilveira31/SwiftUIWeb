/// Small, deterministic calendar primitives for Embedded Swift and the
/// Embedded Core target. Keeping these values in Core avoids activating
/// FoundationInternationalization/ICU for renderer-only applications; the
/// complete Foundation implementation remains in the optional
/// SwiftUIWebInternationalization target.

/// The browser's own time zone, installed by the browser host. Without a host (tests, static rendering) the local zone is
/// UTC, which is what the fixed-offset zones below give too.
public enum _LocalTimeZoneHost {
  public typealias Provider = (Double) -> Int?
  /// The IANA name of the local zone, nil when no host answers.
  public typealias IdentifierProvider = () -> String?
  /// The week of a locale tag (empty for the browser's language): Foundation's first weekday and minimum days.
  public typealias WeekProvider = (String) -> (firstWeekday: Int, minimumDays: Int)?
  /// A non-generic holder, as `_BrowserDateFormatting` keeps its provider: a closure stored in a generic lock is re-abstracted.
  private final class Storage: @unchecked Sendable {
    var provider: Provider = { _ in nil }
    var identifier: IdentifierProvider = { nil }
    var week: WeekProvider = { _ in nil }
  }
  private static let storage = Storage()
  public static func install(_ provider: Provider?) { storage.provider = provider ?? { _ in nil } }
  public static func installZoneAndWeek(identifier: IdentifierProvider?, week: WeekProvider?) {
    storage.identifier = identifier ?? { nil }
    storage.week = week ?? { _ in nil }
  }
  /// Seconds east of UTC in the local zone at `epochSeconds`; nil when no host answers.
  public static func offsetSeconds(epochSeconds: Double) -> Int? { storage.provider(epochSeconds) }
  public static func identifier() -> String? { storage.identifier() }
  public static func weekInfo(locale: String) -> (firstWeekday: Int, minimumDays: Int)? { storage.week(locale) }
}

public struct TimeZone: Hashable, Sendable {
  private let name: String
  private let offset: Int
  /// True for the browser's own zone (`TimeZone.current`): its offset follows the host's rules at each instant.
  private let followsHost: Bool

  /// The IANA name, such as `Europe/Lisbon`. The browser's own zone reads the host's name, and `GMT` without a host.
  public var identifier: String {
    guard followsHost else { return name }
    return _LocalTimeZoneHost.identifier() ?? "GMT"
  }

  public init?(identifier: String) {
    let normalized = identifier.uppercased()
    if normalized == "UTC" || normalized == "GMT" || normalized == "ETC/UTC" {
      name = identifier
      offset = 0
      followsHost = false
      return
    }
    guard normalized.hasPrefix("GMT") || normalized.hasPrefix("UTC") else { return nil }
    let suffix = String(normalized.dropFirst(3))
    guard let parsed = _parseTimeZoneOffset(suffix) else { return nil }
    name = identifier
    offset = parsed
    followsHost = false
  }

  /// The browser's own zone: its offset and identifier come from the host at each read.
  private init(followingHost: Void) {
    name = ""
    offset = 0
    followsHost = true
  }

  public init?(secondsFromGMT seconds: Int) {
    guard (-86_400...86_400).contains(seconds) else { return nil }
    offset = seconds
    followsHost = false
    // Foundation's identifiers: `GMT` for zero, `GMT-0300` otherwise.
    name = seconds == 0 ? "GMT" : "GMT\(_formatTimeZoneOffset(seconds))"
  }

  public init?(abbreviation: String) {
    switch abbreviation.uppercased() {
    case "UTC", "GMT": self.init(secondsFromGMT: 0)
    case "EST": self.init(secondsFromGMT: -5 * 3_600)
    case "EDT": self.init(secondsFromGMT: -4 * 3_600)
    case "CST": self.init(secondsFromGMT: -6 * 3_600)
    case "CDT": self.init(secondsFromGMT: -5 * 3_600)
    case "MST": self.init(secondsFromGMT: -7 * 3_600)
    case "MDT": self.init(secondsFromGMT: -6 * 3_600)
    case "PST": self.init(secondsFromGMT: -8 * 3_600)
    case "PDT": self.init(secondsFromGMT: -7 * 3_600)
    default: return nil
    }
  }

  public static let gmt = TimeZone(secondsFromGMT: 0)!
  public static let current = TimeZone(followingHost: ())
  public static let autoupdatingCurrent = current
  public static let abbreviationDictionary: [String: String] = ["UTC": "UTC", "GMT": "GMT"]

  public func abbreviation(for date: Date = Date()) -> String? { identifier.uppercased() == "UTC" ? "UTC" : identifier }
  public func secondsFromGMT(for date: Date = Date()) -> Int {
    guard followsHost else { return offset }
    return _LocalTimeZoneHost.offsetSeconds(epochSeconds: date.timeIntervalSince1970) ?? 0
  }
  public func isDaylightSavingTime(for date: Date = Date()) -> Bool { false }
  public func daylightSavingTimeOffset(for date: Date = Date()) -> TimeInterval { 0 }
}

public struct DateComponents: Hashable, Sendable {
  public var calendar: Calendar?
  public var timeZone: TimeZone?
  public var era: Int?
  public var year: Int?
  public var month: Int?
  public var day: Int?
  public var hour: Int?
  public var minute: Int?
  public var second: Int?
  public var nanosecond: Int?
  public var weekday: Int?
  public var weekdayOrdinal: Int?
  public var quarter: Int?
  public var weekOfMonth: Int?
  public var weekOfYear: Int?
  public var yearForWeekOfYear: Int?

  public var date: Date? { calendar?.date(from: self) }

  public init(
    calendar: Calendar? = nil,
    timeZone: TimeZone? = nil,
    era: Int? = nil,
    year: Int? = nil,
    month: Int? = nil,
    day: Int? = nil,
    hour: Int? = nil,
    minute: Int? = nil,
    second: Int? = nil,
    nanosecond: Int? = nil,
    weekday: Int? = nil,
    weekdayOrdinal: Int? = nil,
    quarter: Int? = nil,
    weekOfMonth: Int? = nil,
    weekOfYear: Int? = nil,
    yearForWeekOfYear: Int? = nil
  ) {
    self.calendar = calendar
    self.timeZone = timeZone
    self.era = era
    self.year = year
    self.month = month
    self.day = day
    self.hour = hour
    self.minute = minute
    self.second = second
    self.nanosecond = nanosecond
    self.weekday = weekday
    self.weekdayOrdinal = weekdayOrdinal
    self.quarter = quarter
    self.weekOfMonth = weekOfMonth
    self.weekOfYear = weekOfYear
    self.yearForWeekOfYear = yearForWeekOfYear
  }
}

public struct Calendar: Hashable, Sendable {
  public enum Identifier: Hashable, Sendable {
    case gregorian
    case iso8601
  }

  public enum Component: Hashable, Sendable {
    case era, year, month, day, hour, minute, second, nanosecond
    case weekday, weekdayOrdinal, quarter, weekOfMonth, weekOfYear, yearForWeekOfYear
  }

  public let identifier: Identifier
  public var timeZone: TimeZone
  /// Setting a locale takes that locale's week, unless a first weekday or minimum days was assigned: those survive, as
  /// they do on Apple platforms. The default locale is the browser's own.
  public var locale: Locale? {
    didSet {
      guard let locale else { return }
      _applyWeek(locale.identifier)
    }
  }
  /// The first weekday: the assigned value, or the locale's week (read once, when the calendar is made or its locale set).
  /// The stored value is kept as set; every use gets it folded into 1...7, so an app or browser value outside that range
  /// cannot make a negative range downstream.
  public var firstWeekday: Int {
    get { _normalizedWeekday(explicitFirstWeekday ?? weekFirstWeekday) }
    set { explicitFirstWeekday = newValue }
  }
  private func _normalizedWeekday(_ value: Int) -> Int {
    ((value &- 1) % 7 + 7) % 7 + 1
  }
  public var minimumDaysInFirstWeek: Int {
    get { explicitMinimumDays ?? weekMinimumDays }
    set { explicitMinimumDays = newValue }
  }
  // The week is stored, not read again on each access, so a calendar kept in the environment keeps its week.
  private var weekFirstWeekday = 1
  private var weekMinimumDays = 1
  private var explicitFirstWeekday: Int?
  private var explicitMinimumDays: Int?

  public init(identifier: Calendar.Identifier) {
    self.identifier = identifier
    // As Foundation's calendars do, a new calendar works in the user's own time zone and week.
    timeZone = .current
    locale = nil
    _applyWeek("")
  }

  /// The week of `tag` from the host ("" is the browser's language); Sunday as the first day, one day in the first week,
  /// when no host answers.
  private mutating func _applyWeek(_ tag: String) {
    if let week = _LocalTimeZoneHost.weekInfo(locale: tag) {
      weekFirstWeekday = week.firstWeekday
      weekMinimumDays = week.minimumDays
    } else {
      weekFirstWeekday = 1
      weekMinimumDays = 1
    }
  }

  /// Computed, as Foundation's is: the browser's zone and week are read when the calendar is made, not once at launch.
  public static var current: Calendar { Calendar(identifier: .gregorian) }
  public static var autoupdatingCurrent: Calendar { Calendar.current }

  public func dateComponents(_ components: Set<Calendar.Component>, from date: Date) -> DateComponents {
    let seconds = _embeddedClampedSeconds(date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date)))
    let dayNumber = Int64((seconds / 86_400).rounded(.down))
    let daySeconds = seconds - Double(dayNumber) * 86_400
    let civil = _embeddedCivilFromDays(dayNumber)
    let hour = Int(daySeconds / 3_600)
    let minute = Int(daySeconds.truncatingRemainder(dividingBy: 3_600) / 60)
    let second = Int(daySeconds.truncatingRemainder(dividingBy: 60))
    var result = DateComponents(calendar: self, timeZone: timeZone)
    if components.contains(.era) { result.era = 1 }
    if components.contains(.year) { result.year = civil.year }
    if components.contains(.month) { result.month = civil.month }
    if components.contains(.day) { result.day = civil.day }
    if components.contains(.hour) { result.hour = hour }
    if components.contains(.minute) { result.minute = minute }
    if components.contains(.second) { result.second = second }
    if components.contains(.nanosecond) { result.nanosecond = Int((daySeconds - daySeconds.rounded(.down)) * 1_000_000_000) }
    if components.contains(.weekday) { result.weekday = Int((dayNumber + 4).positiveModulo(7)) + 1 }
    if components.contains(.quarter) { result.quarter = (civil.month - 1) / 3 + 1 }
    if components.contains(.weekdayOrdinal) { result.weekdayOrdinal = (civil.day - 1) / 7 + 1 }
    if components.contains(.weekOfYear) || components.contains(.weekOfMonth) || components.contains(.yearForWeekOfYear) {
      let weeks = _weekFields(dayNumber: dayNumber, civil: civil)
      if components.contains(.weekOfYear) { result.weekOfYear = weeks.weekOfYear }
      if components.contains(.weekOfMonth) { result.weekOfMonth = weeks.weekOfMonth }
      if components.contains(.yearForWeekOfYear) { result.yearForWeekOfYear = weeks.yearForWeekOfYear }
    }
    return result
  }

  /// The week fields of a day (`dayNumber` counts days since 1970), numbered as ICU does for this calendar's week: week 1 of
  /// a year is the first week, starting on `firstWeekday`, that has at least `minimumDaysInFirstWeek` days in the year; the
  /// days before it belong to the last week of the year before (and to week 0 of a month). The week-based year follows.
  private func _weekFields(dayNumber: Int64, civil: (year: Int, month: Int, day: Int)) -> (yearForWeekOfYear: Int, weekOfYear: Int, weekOfMonth: Int) {
    let first = Int64(Swift.min(Swift.max(firstWeekday, 1), 7))
    let minimum = Int64(Swift.min(Swift.max(minimumDaysInFirstWeek, 1), 7))
    /// The first day of week 1 of the period that starts on `firstDay`.
    func firstWeekStart(of firstDay: Int64) -> Int64 {
      let weekdayOfFirstDay = (firstDay + 4).positiveModulo(7) + 1
      let offset = (weekdayOfFirstDay - first).positiveModulo(7)
      return 7 - offset >= minimum ? firstDay - offset : firstDay - offset + 7
    }
    let thisYear = firstWeekStart(of: _embeddedDaysFromCivil(year: civil.year, month: 1, day: 1))
    let nextYear = firstWeekStart(of: _embeddedDaysFromCivil(year: civil.year + 1, month: 1, day: 1))
    let weekYear: Int
    let yearStart: Int64
    if dayNumber >= nextYear {
      weekYear = civil.year + 1
      yearStart = nextYear
    } else if dayNumber >= thisYear {
      weekYear = civil.year
      yearStart = thisYear
    } else {
      weekYear = civil.year - 1
      yearStart = firstWeekStart(of: _embeddedDaysFromCivil(year: civil.year - 1, month: 1, day: 1))
    }
    let monthStart = firstWeekStart(of: _embeddedDaysFromCivil(year: civil.year, month: civil.month, day: 1))
    let weekOfMonth = dayNumber >= monthStart ? Int((dayNumber - monthStart) / 7) + 1 : 0
    return (weekYear, Int((dayNumber - yearStart) / 7) + 1, weekOfMonth)
  }

  public func dateComponents(in timeZone: TimeZone, from date: Date) -> DateComponents {
    var calendar = self
    calendar.timeZone = timeZone
    return calendar.dateComponents(
      [.era, .year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday],
      from: date
    )
  }

  public func component(_ component: Calendar.Component, from date: Date) -> Int {
    let components = dateComponents([component], from: date)
    switch component {
    case .era: return components.era ?? 0
    case .year: return components.year ?? 0
    case .month: return components.month ?? 0
    case .day: return components.day ?? 0
    case .hour: return components.hour ?? 0
    case .minute: return components.minute ?? 0
    case .second: return components.second ?? 0
    case .nanosecond: return components.nanosecond ?? 0
    case .weekday: return components.weekday ?? 0
    case .weekdayOrdinal: return components.weekdayOrdinal ?? 0
    case .quarter: return components.quarter ?? 0
    case .weekOfMonth: return components.weekOfMonth ?? 0
    case .weekOfYear: return components.weekOfYear ?? 0
    case .yearForWeekOfYear: return components.yearForWeekOfYear ?? 0
    }
  }

  public func date(from components: DateComponents) -> Date? {
    guard let year = components.year, let month = components.month, let day = components.day,
          (1...12).contains(month), (1...31).contains(day) else { return nil }
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    let second = components.second ?? 0
    let fraction = Double(components.nanosecond ?? 0) / 1_000_000_000
    let civilDays = _embeddedDaysFromCivil(year: year, month: month, day: day)
    // In Double: Int is 32 bits in the browser build, where a million hours overflows `hour * 3_600`.
    let local = Double(civilDays) * 86_400 + Double(hour) * 3_600 + Double(minute) * 60 + Double(second) + fraction
    let zone = components.timeZone ?? timeZone
    // The wall time is in `zone`, resolved by its offsets either side of the reading: one the clocks skipped keeps its minutes
    // with the offset from before (02:30 becomes 03:30) and one they repeated takes the first occurrence, as Foundation does.
    return _instantOfWallTime(
      Date(timeIntervalSince1970: local), offsetAt: { zone.secondsFromGMT(for: $0) },
      gap: .nextPreservingSmallerComponents, repeated: .first)
  }

  public func date(byAdding component: Calendar.Component, value: Int, to date: Date, wrappingComponents: Bool = false) -> Date? {
    // Hours and smaller are exact intervals, and adding seconds is exact for any magnitude, where overflowing a
    // day-of-month field (a day of -55) would not build a date at all. A day keeps its wall-clock time across a
    // daylight-saving change, as Foundation does.
    switch component {
    case .day:
      // Adding no day is the instant itself: its wall reading may name two instants (the hour the clocks repeat).
      if value == 0 { return date }
      // The wall reading a day further on, resolved in the zone: a reading in the hour the clocks skipped keeps its minutes
      // with the offset from before (02:30 becomes 03:30), one in a repeated hour takes the first occurrence.
      let zone = timeZone
      let wall = date.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: date)) + Double(value) * 86_400
      return _instantOfWallTime(
        Date(timeIntervalSince1970: wall), offsetAt: { zone.secondsFromGMT(for: $0) },
        gap: .nextPreservingSmallerComponents, repeated: .first)
    case .hour: return date.addingTimeInterval(Double(value) * 3_600)
    case .minute: return date.addingTimeInterval(Double(value) * 60)
    case .second: return date.addingTimeInterval(Double(value))
    case .nanosecond: return date.addingTimeInterval(Double(value) / 1_000_000_000)
    default: break
    }
    var components = dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
    switch component {
    // Past Int's range (32 bits in the browser build) there is no such date: nil, rather than a trap.
    case .year:
      let (year, overflow) = (components.year ?? 0).addingReportingOverflow(value)
      if overflow { return nil }
      components.year = year
    case .month:
      let (months, multiplied) = (components.year ?? 0).multipliedReportingOverflow(by: 12)
      let (shifted, added) = months.addingReportingOverflow((components.month ?? 1) - 1)
      let (totalMonths, moved) = shifted.addingReportingOverflow(value)
      if multiplied || added || moved || totalMonths < Int.min + 11 { return nil }
      let normalizedYear = totalMonths >= 0 ? totalMonths / 12 : (totalMonths - 11) / 12
      components.year = normalizedYear
      components.month = totalMonths - normalizedYear * 12 + 1
    case .day: components.day = (components.day ?? 0) + value
    case .hour: components.hour = (components.hour ?? 0) + value
    case .minute: components.minute = (components.minute ?? 0) + value
    case .second: components.second = (components.second ?? 0) + value
    case .nanosecond: components.nanosecond = (components.nanosecond ?? 0) + value
    default: return nil
    }
    // A day that the new month does not have (January 31 plus a month, February 29 plus a year) is the month's last, as
    // Foundation clamps it, not the first days of the month after.
    if component == .year || component == .month, let year = components.year, let month = components.month, let day = components.day {
      components.day = Swift.min(day, _embeddedDaysInMonth(year: year, month: month))
    }
    return self.date(from: components)
  }

  public func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool = false) -> Date? {
    var result: Date? = date
    for (component, value) in [
      (Component.year, components.year), (Component.month, components.month),
      (Component.day, components.day), (Component.hour, components.hour),
      (Component.minute, components.minute), (Component.second, components.second),
      (Component.nanosecond, components.nanosecond)
    ] {
      if let value, let current = result { result = self.date(byAdding: component, value: value, to: current, wrappingComponents: wrappingComponents) }
    }
    return result
  }

  /// Whole days, hours, minutes and seconds between two dates (truncated
  /// toward zero, like Foundation); larger units are not supported here.
  public func dateComponents(_ components: Set<Calendar.Component>, from start: Date, to end: Date) -> DateComponents {
    let seconds = end.timeIntervalSince1970 - start.timeIntervalSince1970
    var result = DateComponents(calendar: self, timeZone: timeZone)
    var remainder = seconds
    if components.contains(.day) {
      // Calendar days: the count of wall-clock days between the two readings, so a day with a daylight-saving change (23 or
      // 25 hours) is one day. The rest is the time left after that many days have been added to `start`.
      let wallSeconds = seconds + Double(timeZone.secondsFromGMT(for: end) - timeZone.secondsFromGMT(for: start))
      var days = (wallSeconds / 86_400).rounded(.towardZero)
      if wallSeconds.isFinite, abs(days) < 1e8 {
        func shifted(_ count: Double) -> Date { self.date(byAdding: .day, value: Int(count), to: start) ?? start }
        if seconds >= 0 && shifted(days) > end { days -= 1 }
        if seconds < 0 && shifted(days) < end { days += 1 }
        remainder = end.timeIntervalSince1970 - shifted(days).timeIntervalSince1970
      } else {
        // A span too long to step through in days: plain 86,400-second days.
        days = (seconds / 86_400).rounded(.towardZero)
        remainder -= days * 86_400
      }
      result.day = _embeddedWholeUnits(days)
    }
    if components.contains(.hour) {
      let hours = (remainder / 3_600).rounded(.towardZero)
      result.hour = _embeddedWholeUnits(hours)
      remainder -= hours * 3_600
    }
    if components.contains(.minute) {
      let minutes = (remainder / 60).rounded(.towardZero)
      result.minute = _embeddedWholeUnits(minutes)
      remainder -= minutes * 60
    }
    if components.contains(.second) { result.second = _embeddedWholeUnits(remainder.rounded(.towardZero)) }
    return result
  }

  public func startOfDay(for date: Date) -> Date {
    let components = dateComponents([.year, .month, .day], from: date)
    return self.date(from: components) ?? date
  }

  public func isDateInToday(_ date: Date) -> Bool {
    dateComponents([.year, .month, .day], from: date) == dateComponents([.year, .month, .day], from: Date())
  }
}

private func _parseTimeZoneOffset(_ raw: String) -> Int? {
  guard !raw.isEmpty else { return 0 }
  let sign = raw.first == "-" ? -1 : 1
  let digits = raw.first == "+" || raw.first == "-" ? String(raw.dropFirst()) : raw
  // `HH:MM`, `HHMM` (Foundation's own spelling, `GMT-0300`) or `HH`.
  let parts: [Substring] = digits.contains(":") ? digits.split(separator: ":")
    : digits.count == 4 ? [digits.prefix(2), digits.suffix(2)] : [Substring(digits)]
  guard let first = parts.first, let hours = Int(first), (0...23).contains(hours) else { return nil }
  let minutes = parts.count > 1 ? Int(parts[1]) ?? -1 : 0
  guard (0..<60).contains(minutes) else { return nil }
  let (hourSeconds, hourOverflow) = hours.multipliedReportingOverflow(by: 3_600)
  let (offset, sumOverflow) = hourSeconds.addingReportingOverflow(minutes * 60)
  guard !hourOverflow, !sumOverflow else { return nil }
  return sign * offset
}

private func _formatTimeZoneOffset(_ seconds: Int) -> String {
  let sign = seconds < 0 ? "-" : "+"
  let absolute = abs(seconds)
  return "\(sign)\(_twoDigitsEmbedded(absolute / 3_600))\(_twoDigitsEmbedded((absolute / 60) % 60))"
}

private func _twoDigitsEmbedded(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }

/// The number of days in a month of the proleptic Gregorian calendar.
private func _embeddedDaysInMonth(year: Int, month: Int) -> Int {
  switch month {
  case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
  case 4, 6, 9, 11: return 30
  default: return 31
  }
}

private func _embeddedDaysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
  let y = Int64(year) - (month <= 2 ? 1 : 0)
  let era = (y >= 0 ? y : y - 399) / 400
  let yearOfEra = y - era * 400
  let monthPrime = Int64(month) + (month > 2 ? -3 : 9)
  let dayOfYear = (153 * monthPrime + 2) / 5 + Int64(day) - 1
  let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
  return era * 146_097 + dayOfEra - 719_468
}

private func _embeddedCivilFromDays(_ days: Int64) -> (year: Int, month: Int, day: Int) {
  let z = days + 719_468
  let era = (z >= 0 ? z : z - 146_096) / 146_097
  let dayOfEra = z - era * 146_097
  let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
  var year = yearOfEra + era * 400
  let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
  let monthPrime = (5 * dayOfYear + 2) / 153
  let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
  let month = monthPrime + (monthPrime < 10 ? 3 : -9)
  year += month <= 2 ? 1 : 0
  return (Int(year), Int(month), Int(day))
}

private extension Int64 {
  func positiveModulo(_ value: Int64) -> Int64 { ((self % value) + value) % value }
}

/// Seconds clamped to the range the calendar converts: 2^39 days, about 1.5 billion years, so the civil year still fits the
/// 32-bit Int of wasm32. Beyond it the Int64 day count would trap. A NaN reads as the epoch.
private func _embeddedClampedSeconds(_ seconds: Double) -> Double {
  if seconds.isNaN { return 0 }
  let limit = 549_755_813_888.0 * 86_400
  return min(max(seconds, -limit), limit)
}

/// A whole number of days, hours, minutes or seconds as Int, clamped to Int's range; `Int(Double)` traps outside it.
private func _embeddedWholeUnits(_ value: Double) -> Int {
  if value.isNaN { return 0 }
  if value <= Double(Int.min) { return Int.min }
  if value >= Double(Int.max) { return Int.max }
  return Int(value)
}


/// How a wall time that does not exist (the clocks went forward over it) is resolved.
package enum _WallTimeGap {
  /// The first instant after the gap.
  case next
  /// The wall reading with the offset from before the gap (02:30 becomes 03:30).
  case nextPreservingSmallerComponents
  /// The wall reading with the offset from after the gap (02:30 becomes 01:30).
  case previousPreservingSmallerComponents
  case strict
}

/// Which occurrence of a wall time that happens twice (the clocks went back over it) is chosen.
package enum _WallTimeRepeat {
  case first
  case last
}

/// The instant whose wall time is `wall` (a reading taken as if it were UTC) in a zone whose offset (seconds east of UTC) at an
/// instant `offsetAt` answers. A zone's offset changes by at most a transition a day, so the offsets a day before and a day
/// after the wall time give the two instants it can name: both are valid when the clock went back (a repeated time), neither
/// when it went forward (a skipped one).
package func _instantOfWallTime(
  _ wall: Date, offsetAt offset: (Date) -> Int, gap: _WallTimeGap, repeated: _WallTimeRepeat
) -> Date? {
  let before = offset(wall.addingTimeInterval(-86_400))
  let after = offset(wall.addingTimeInterval(86_400))
  let withBefore = wall.addingTimeInterval(-Double(before))
  guard before != after else { return withBefore }
  let withAfter = wall.addingTimeInterval(-Double(after))
  let beforeHolds = offset(withBefore) == before
  let afterHolds = offset(withAfter) == after
  if beforeHolds && afterHolds {
    return repeated == .first ? Swift.min(withBefore, withAfter) : Swift.max(withBefore, withAfter)
  }
  if beforeHolds { return withBefore }
  if afterHolds { return withAfter }
  switch gap {
  case .strict: return nil
  case .nextPreservingSmallerComponents: return withBefore
  case .previousPreservingSmallerComponents: return withAfter
  case .next:
    // The first instant of the new offset: where the skipped hour begins to be missing.
    var low = Swift.min(withBefore, withAfter)
    var high = Swift.max(withBefore, withAfter)
    let lowOffset = offset(low)
    while high.timeIntervalSince(low) > 1 {
      let middle = Date(timeIntervalSince1970: ((low.timeIntervalSince1970 + high.timeIntervalSince1970) / 2).rounded(.down))
      if offset(middle) == lowOffset { low = middle } else { high = middle }
    }
    return high
  }
}

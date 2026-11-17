// Foundation value types and helpers the browser build lacks, for application code written once against Foundation.
// Embedded/WASI only, behind the same gate SwiftUIWebCore uses: native builds keep the real Foundation.
import SwiftUIWebBrowserIO
import SwiftUIWebCore
import SwiftUIWebInternationalization

// MARK: Errors and comparison

/// Foundation's `LocalizedError`. Embedded Swift cannot cast an error to a protocol, so the browser build names plain
/// `Error` and gives it the same optional descriptions: a conformer's own `errorDescription` is still what it declares,
/// and code reading it through `any LocalizedError` gets the default.
public typealias LocalizedError = Error

extension Error {
  public var errorDescription: String? { nil }
  public var failureReason: String? { nil }
  public var recoverySuggestion: String? { nil }
  public var helpAnchor: String? { nil }
  /// Foundation's `Error.localizedDescription`; the browser build has no reflection to describe an arbitrary error.
  public var localizedDescription: String { errorDescription ?? "The operation couldn’t be completed." }
}

// `ComparisonResult` lives in SwiftUIWebCore (TableSortComparators.swift) beside `SortComparator`.

extension String {
  /// Case-insensitive containment. The browser build compares lowercase scalars; a locale-aware comparison needs `Intl`.
  public func localizedCaseInsensitiveContains(_ other: String) -> Bool {
    lowercased().contains(other.lowercased())
  }

  public func localizedStandardContains(_ other: String) -> Bool {
    localizedCaseInsensitiveContains(other)
  }

  public func localizedCompare(_ other: String) -> ComparisonResult {
    let lhs = lowercased()
    let rhs = other.lowercased()
    if lhs == rhs { return self == other ? .orderedSame : (self < other ? .orderedAscending : .orderedDescending) }
    return lhs < rhs ? .orderedAscending : .orderedDescending
  }

  public func caseInsensitiveCompare(_ other: String) -> ComparisonResult {
    let lhs = lowercased()
    let rhs = other.lowercased()
    return lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
  }
}

// Lowering targets for `error.localizedDescription` and `error?.errorDescription`: Embedded Swift cannot call a
// protocol-extension method on an error existential, so the source lowering routes them here. The browser build has no
// reflection to describe an arbitrary error, so every error reads as the same sentence.
public func _embeddedErrorDescription(_ error: any Error) -> String { "The operation couldn’t be completed." }

public func _embeddedOptionalErrorDescription(_ error: (any Error)?) -> String? {
  error == nil ? nil : "The operation couldn’t be completed."
}

// MARK: Dates

extension Calendar {
  /// The day before and the day after are found by adding a calendar day, not 86,400 seconds: a day with a daylight-saving
  /// change is 23 or 25 hours long.
  public func isDateInYesterday(_ date: Date) -> Bool {
    self.date(byAdding: .day, value: -1, to: startOfDay(for: Date())).map { startOfDay(for: date) == $0 } ?? false
  }

  public func isDateInTomorrow(_ date: Date) -> Bool {
    self.date(byAdding: .day, value: 1, to: startOfDay(for: Date())).map { startOfDay(for: date) == $0 } ?? false
  }

  /// Saturday and Sunday, as in the Gregorian calendar (weekday 1 is Sunday).
  public func isDateInWeekend(_ date: Date) -> Bool {
    let weekday = component(.weekday, from: date)
    return weekday == 1 || weekday == 7
  }

  /// Foundation's `isDate(_:inSameDayAs:)`: the same year, month and day in this calendar's time zone.
  public func isDate(_ date1: Date, inSameDayAs date2: Date) -> Bool {
    isDate(date1, equalTo: date2, toGranularity: .day)
  }

  /// Equal down to `component`: `.month` compares the year and the month, `.hour` the day and the hour, and so on.
  /// Weeks, quarters and weekdays compare the field they name within the year (or day) it belongs to.
  public func isDate(_ date1: Date, equalTo date2: Date, toGranularity component: Calendar.Component) -> Bool {
    let fields: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second, .nanosecond]
    let units: [Calendar.Component]
    switch component {
    case .era: units = [.era]
    case .hour, .minute, .second:
      // The same clock unit of the same instant's day: compared as the instants the units start at, because in the hour a zone
      // repeats two different instants have the same wall-clock fields.
      let unit: Double = component == .hour ? 3_600 : component == .minute ? 60 : 1
      func start(_ date: Date) -> Date {
        Calendar._startOfClockUnit(containing: date, unit: unit, offset: Double(timeZone.secondsFromGMT(for: date)))
      }
      return start(date1) == start(date2)
    case .year, .month, .day, .nanosecond:
      units = Array(fields[0 ... (fields.firstIndex(of: component) ?? 0)])
    case .quarter: units = [.year, .quarter]
    case .weekOfYear: units = [.yearForWeekOfYear, .weekOfYear]
    case .yearForWeekOfYear: units = [.yearForWeekOfYear]
    case .weekOfMonth: units = [.year, .month, .weekOfMonth]
    case .weekday, .weekdayOrdinal: units = [.year, .month, .day]
    }
    return units.allSatisfy { self.component($0, from: date1) == self.component($0, from: date2) }
  }

  /// Foundation's `dateInterval(of:for:)`: the span of `component` (a day, a month, a week, ...) that contains `date`.
  /// Nil for the components a calendar cannot bound this way, as Foundation returns.
  public func dateInterval(of component: Calendar.Component, for date: Date) -> DateInterval? {
    guard let start = _startOf(component, containing: date) else { return nil }
    var unit = component
    var value = 1
    switch component {
    case .quarter: unit = .month; value = 3
    case .weekOfYear, .weekOfMonth: unit = .day; value = 7
    default: break
    }
    guard let end = self.date(byAdding: unit, value: value, to: start) else { return nil }
    return DateInterval(start: start, end: end)
  }

  private func _startOf(_ component: Calendar.Component, containing instant: Date) -> Date? {
    let now = dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: instant)
    var start = DateComponents()
    start.year = now.year
    switch component {
    case .year: start.month = 1; start.day = 1
    case .quarter: start.month = ((now.month ?? 1) - 1) / 3 * 3 + 1; start.day = 1
    case .month: start.month = now.month; start.day = 1
    case .day, .weekOfYear, .weekOfMonth:
      start.month = now.month; start.day = now.day
    case .hour, .minute, .second:
      // Measured back from the instant itself, not rebuilt from wall-clock fields: in the hour a zone repeats, the fields
      // do not say which occurrence holds `instant`.
      let unit: Double = component == .hour ? 3_600 : component == .minute ? 60 : 1
      return Calendar._startOfClockUnit(
        containing: instant, unit: unit, offset: Double(timeZone.secondsFromGMT(for: instant)))
    default: return nil
    }
    guard let first = self.date(from: start) else { return nil }
    guard component == .weekOfYear || component == .weekOfMonth else { return first }
    // A week starts on `firstWeekday`, so step back over the days since then.
    let daysSince = ((now.weekday ?? 1) - firstWeekday + 7) % 7
    return self.date(byAdding: .day, value: -daysSince, to: first)
  }

  /// The start of the hour, minute or second (`unit` seconds) of the wall clock that holds `instant`, in a zone whose offset
  /// at `instant` is `offset`. The wall clock turns over at multiples of the unit whatever the zone's offset is.
  package static func _startOfClockUnit(containing instant: Date, unit: Double, offset: Double) -> Date {
    let seconds = instant.timeIntervalSince1970
    let local = seconds + offset
    return Date(timeIntervalSince1970: seconds - (local - (local / unit).rounded(.down) * unit))
  }

  /// Foundation's `range(of:in:for:)` for the pairs calendar layouts use (days of a month or year, months of a year,
  /// hours of a day, minutes of an hour, seconds of a minute). Other pairs are nil, as Foundation returns for them.
  public func range(of smaller: Calendar.Component, in larger: Calendar.Component, for date: Date) -> Range<Int>? {
    switch (smaller, larger) {
    case (.day, .month), (.day, .year):
      guard let interval = dateInterval(of: larger, for: date) else { return nil }
      return 1 ..< Int((interval.duration / 86_400).rounded()) + 1
    case (.month, .year): return 1 ..< 13
    case (.hour, .day): return 0 ..< 24
    case (.minute, .hour): return 0 ..< 60
    case (.second, .minute): return 0 ..< 60
    default: return nil
    }
  }

  /// Foundation's `date(bySettingHour:minute:second:of:...)`: that wall-clock time in this calendar's time zone, on the day
  /// of `date` when searching `.forward` and on the day before when searching `.backward`, as Foundation searches from
  /// the start of the day. A wall time that happens twice takes `repeatedTimePolicy`'s occurrence. One the clocks skipped
  /// moves to the end of the skipped hour searching forward, and follows `matchingPolicy` searching backward; `.strict`
  /// moves on, in `direction`, to the nearest day on which the time exists.
  public func date(
    bySettingHour hour: Int, minute: Int, second: Int, of date: Date,
    matchingPolicy: Calendar.MatchingPolicy = .nextTime,
    repeatedTimePolicy: Calendar.RepeatedTimePolicy = .first,
    direction: Calendar.SearchDirection = .forward
  ) -> Date? {
    guard (0 ... 23).contains(hour), (0 ... 59).contains(minute), (0 ... 59).contains(second) else { return nil }
    guard let utc = TimeZone(secondsFromGMT: 0) else { return nil }
    var wallCalendar = self
    wallCalendar.timeZone = utc
    var parts = dateComponents([.year, .month, .day], from: date)
    parts.timeZone = utc
    guard let wallDay = wallCalendar.date(from: parts) else { return nil }
    let zone = timeZone
    return Calendar._instant(
      settingTimeOfDay: hour * 3_600 + minute * 60 + second, onWallDay: wallDay, offsetAt: { zone.secondsFromGMT(for: $0) },
      matchingPolicy: matchingPolicy, repeatedTimePolicy: repeatedTimePolicy, direction: direction)
  }

  /// The search of `date(bySettingHour:...)` apart from any zone: `wallDay` is the day's midnight read as if it were UTC,
  /// `seconds` the time of day, and `offsetAt` answers the zone's offset (seconds east of UTC) at an instant.
  package static func _instant(
    settingTimeOfDay seconds: Int, onWallDay wallDay: Date, offsetAt offset: (Date) -> Int,
    matchingPolicy: Calendar.MatchingPolicy, repeatedTimePolicy: Calendar.RepeatedTimePolicy,
    direction: Calendar.SearchDirection
  ) -> Date? {
    let step: Double = direction == .forward ? 86_400 : -86_400
    var day = direction == .forward ? wallDay : wallDay.addingTimeInterval(step)
    let policy: Calendar.MatchingPolicy = direction == .forward && matchingPolicy != .strict ? .nextTime : matchingPolicy
    // Only `.strict` gives nil, on a day the time was skipped; a zone skips it on a single day at a time, so the search
    // ends on the next day or the one after.
    for _ in 0 ..< 7 {
      if let instant = _instant(
        ofWallTime: day.addingTimeInterval(Double(seconds)), offsetAt: offset,
        matchingPolicy: policy, repeatedTimePolicy: repeatedTimePolicy) {
        return instant
      }
      day = day.addingTimeInterval(step)
    }
    return nil
  }

  /// The resolution itself, apart from any zone (see `_instantOfWallTime`): `wall` is the wall-clock reading taken as if it
  /// were UTC, and `offsetAt` answers the zone's offset (seconds east of UTC) at an instant.
  package static func _instant(
    ofWallTime wall: Date, offsetAt offset: (Date) -> Int,
    matchingPolicy: Calendar.MatchingPolicy, repeatedTimePolicy: Calendar.RepeatedTimePolicy
  ) -> Date? {
    let gap: _WallTimeGap
    switch matchingPolicy {
    case .nextTime: gap = .next
    case .nextTimePreservingSmallerComponents: gap = .nextPreservingSmallerComponents
    case .previousTimePreservingSmallerComponents: gap = .previousPreservingSmallerComponents
    case .strict: gap = .strict
    }
    return _instantOfWallTime(wall, offsetAt: offset, gap: gap, repeated: repeatedTimePolicy == .first ? .first : .last)
  }
}

extension Calendar {
  /// Foundation's `Calendar.SearchDirection`, the direction `date(bySettingHour:...)` searches in.
  public enum SearchDirection: Hashable, Sendable {
    case forward
    case backward
  }

  /// Foundation's `Calendar.RepeatedTimePolicy`: which occurrence of a time that happens twice is chosen.
  public enum RepeatedTimePolicy: Hashable, Sendable {
    case first
    case last
  }

  /// Foundation's `Calendar.MatchingPolicy`: how a time that does not exist is resolved.
  public enum MatchingPolicy: Hashable, Sendable {
    case nextTime
    case nextTimePreservingSmallerComponents
    case previousTimePreservingSmallerComponents
    case strict
  }
}

/// A span of time: a `start` and a `duration` in seconds, with `end` derived from them (Foundation's `DateInterval`).
public struct DateInterval: Comparable, Hashable, Sendable {
  public var start: Date
  public var duration: TimeInterval

  public var end: Date {
    get { start + duration }
    set { duration = newValue.timeIntervalSince(start) }
  }

  public init() {
    start = Date(timeIntervalSince1970: 0)
    duration = 0
  }

  public init(start: Date, end: Date) {
    self.start = start
    duration = end.timeIntervalSince(start)
  }

  public init(start: Date, duration: TimeInterval) {
    self.start = start
    self.duration = duration
  }

  /// Includes both `start` and `end`, as Foundation's closed interval does (an interval of no duration holds its start).
  public func contains(_ date: Date) -> Bool { start <= date && date <= end }

  /// Orders by start, then by duration, as Foundation's `compare(_:)` does.
  public func compare(_ dateInterval: DateInterval) -> ComparisonResult {
    if start != dateInterval.start { return start < dateInterval.start ? .orderedAscending : .orderedDescending }
    if duration == dateInterval.duration { return .orderedSame }
    return duration < dateInterval.duration ? .orderedAscending : .orderedDescending
  }

  public static func < (lhs: DateInterval, rhs: DateInterval) -> Bool { lhs.compare(rhs) == .orderedAscending }
}

extension Date {
  public static func + (lhs: Date, rhs: TimeInterval) -> Date { lhs.addingTimeInterval(rhs) }
  public static func - (lhs: Date, rhs: TimeInterval) -> Date { lhs.addingTimeInterval(-rhs) }
  public static func += (lhs: inout Date, rhs: TimeInterval) { lhs.addTimeInterval(rhs) }
  public static func -= (lhs: inout Date, rhs: TimeInterval) { lhs.addTimeInterval(-rhs) }
}

// MARK: Numbers

/// A decimal number. The browser build keeps it in a `Double`: exact for the prices and percentages an app shows, not
/// for arbitrary-precision arithmetic.
public struct Decimal: Hashable, Comparable, Sendable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
  package var doubleValue: Double

  public init(_ value: Double) { doubleValue = value }
  public init(_ value: Int) { doubleValue = Double(value) }
  public init(integerLiteral value: Int) { doubleValue = Double(value) }
  public init(floatLiteral value: Double) { doubleValue = value }

  public static func < (lhs: Decimal, rhs: Decimal) -> Bool { lhs.doubleValue < rhs.doubleValue }
  public static func + (lhs: Decimal, rhs: Decimal) -> Decimal { Decimal(lhs.doubleValue + rhs.doubleValue) }
  public static func - (lhs: Decimal, rhs: Decimal) -> Decimal { Decimal(lhs.doubleValue - rhs.doubleValue) }
  public static func * (lhs: Decimal, rhs: Decimal) -> Decimal { Decimal(lhs.doubleValue * rhs.doubleValue) }
  public static func / (lhs: Decimal, rhs: Decimal) -> Decimal { Decimal(lhs.doubleValue / rhs.doubleValue) }
  public static func += (lhs: inout Decimal, rhs: Decimal) { lhs.doubleValue += rhs.doubleValue }
  public static func -= (lhs: inout Decimal, rhs: Decimal) { lhs.doubleValue -= rhs.doubleValue }
  public static func *= (lhs: inout Decimal, rhs: Decimal) { lhs.doubleValue *= rhs.doubleValue }
  public static prefix func - (value: Decimal) -> Decimal { Decimal(-value.doubleValue) }
}

extension Double {
  public init(_ value: Decimal) { self = value.doubleValue }
}

extension Decimal {
  /// `Decimal.formatted(_:)` with a number format style (`.percent`, `.currency(code:)`, ...).
  public func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Double {
    style.format(doubleValue)
  }

  public func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Decimal {
    style.format(self)
  }
}

/// A dimension of measurement (temperature here); `symbol` is what a formatter prints.
open class Unit: NSObject, @unchecked Sendable {
  public let symbol: String
  public init(symbol: String) { self.symbol = symbol; super.init() }
  /// Foundation's `NSUnit` equality: the same class and symbol.
  package override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? Unit else { return false }
    return ObjectIdentifier(type(of: self)) == ObjectIdentifier(type(of: other)) && symbol == other.symbol
  }
  package override var hash: Int { symbol.hashValue }
  /// The value in the dimension's base unit (meters, kilograms, kelvin); the identity for a unit that is its own base.
  package func _baseValue(_ value: Double) -> Double { value }
  /// The inverse of `_baseValue(_:)`.
  package func _value(fromBase value: Double) -> Double { value }
}

public final class UnitTemperature: Unit, @unchecked Sendable {
  public static let kelvin = UnitTemperature(symbol: "K")
  public static let celsius = UnitTemperature(symbol: "°C")
  public static let fahrenheit = UnitTemperature(symbol: "°F")

  override package func _baseValue(_ value: Double) -> Double { toKelvin(value) }
  override package func _value(fromBase value: Double) -> Double { fromKelvin(value) }

  func toKelvin(_ value: Double) -> Double {
    if self == UnitTemperature.celsius { return value + 273.15 }
    if self == UnitTemperature.fahrenheit { return (value + 459.67) * 5 / 9 }
    return value
  }

  func fromKelvin(_ value: Double) -> Double {
    if self == UnitTemperature.celsius { return value - 273.15 }
    if self == UnitTemperature.fahrenheit { return value * 9 / 5 - 459.67 }
    return value
  }

  /// The CLDR unit name, as the locale preferences and `Intl.NumberFormat` know it.
  var identifier: String {
    if self == UnitTemperature.celsius { return "celsius" }
    if self == UnitTemperature.fahrenheit { return "fahrenheit" }
    return "kelvin"
  }

  var wideName: String {
    if self == UnitTemperature.celsius { return "degrees Celsius" }
    if self == UnitTemperature.fahrenheit { return "degrees Fahrenheit" }
    return "kelvin"
  }

  static func named(_ identifier: String) -> UnitTemperature {
    switch identifier {
    case "celsius": UnitTemperature.celsius
    case "fahrenheit": UnitTemperature.fahrenheit
    default: UnitTemperature.kelvin
    }
  }
}

public struct Measurement<UnitType: Unit>: Hashable, Sendable {
  public var value: Double
  public let unit: UnitType

  public init(value: Double, unit: UnitType) {
    self.value = value
    self.unit = unit
  }
}

extension Measurement {
  public func converted(to otherUnit: UnitType) -> Measurement<UnitType> {
    Measurement(value: otherUnit._value(fromBase: unit._baseValue(value)), unit: otherUnit)
  }
}

// MARK: Identity and bundles

/// A universally unique identifier (random, version 4).
public struct UUID: Hashable, Comparable, Sendable, CustomStringConvertible {
  private let high: UInt64
  private let low: UInt64

  public init() {
    // Version 4, variant 1: the fixed bits of RFC 4122.
    high = (UInt64.random(in: 0 ... UInt64.max) & 0xFFFF_FFFF_FFFF_0FFF) | 0x0000_0000_0000_4000
    low = (UInt64.random(in: 0 ... UInt64.max) & 0x3FFF_FFFF_FFFF_FFFF) | 0x8000_0000_0000_0000
  }

  public init?(uuidString: String) {
    // Foundation's form only: 8-4-4-4-12 ASCII hex digits. Dashes elsewhere, or full-width digits, would let two different
    // strings name one identity.
    let characters = Array(uuidString)
    guard characters.count == 36 else { return nil }
    for (index, character) in characters.enumerated() {
      if index == 8 || index == 13 || index == 18 || index == 23 {
        guard character == "-" else { return nil }
      } else {
        guard character.isASCII, character.isHexDigit else { return nil }
      }
    }
    let hex = characters.filter { $0 != "-" }
    var value: UInt64 = 0
    var parts: [UInt64] = []
    for (index, character) in hex.enumerated() {
      guard let digit = character.hexDigitValue else { return nil }
      value = (value << 4) | UInt64(digit)
      if index % 16 == 15 { parts.append(value); value = 0 }
    }
    high = parts[0]
    low = parts[1]
  }

  public var uuidString: String {
    let digits = Array("0123456789ABCDEF")
    var text = ""
    for position in 0 ..< 32 {
      let word = position < 16 ? high : low
      let shift = UInt64((15 - position % 16) * 4)
      text.append(digits[Int((word >> shift) & 0xF)])
      if position == 7 || position == 11 || position == 15 || position == 19 { text.append("-") }
    }
    return text
  }

  public var description: String { uuidString }

  public static func < (lhs: UUID, rhs: UUID) -> Bool {
    lhs.high != rhs.high ? lhs.high < rhs.high : lhs.low < rhs.low
  }
}

extension Bundle {
  /// What the application declares about itself (name, version). A web page has no Info.plist, so it is empty unless
  /// the application fills it in at launch.
  @_spi(BrowserHost) nonisolated(unsafe) public static var webInfoDictionary: [String: String] = .init()

  /// The bundle's Info.plist, as the application declared it in `webInfoDictionary`.
  public var infoDictionary: [String: String]? { Bundle.webInfoDictionary }
}

extension Date {
  public init(timeIntervalSinceNow interval: TimeInterval) {
    self = Date().addingTimeInterval(interval)
  }
}

extension Measurement {
  /// "19°C": the rounded value and the unit's symbol. A locale-aware formatter needs `Intl.NumberFormat` with units.
  public func formatted() -> String {
    // Int64(exactly:): Int is 32 bits in the browser build, and a value from the network can be any Double.
    "\(Int64(exactly: value.rounded()).map { String($0) } ?? "\(value)")\(unit.symbol)"
  }
}

// MARK: Printing

/// `print(_:_:)` with two strings, separated by a space as the standard library does. Embedded Swift's `print`
/// takes a single value.
public func print(_ first: String, _ second: String) { print(first + " " + second) }

public func print(_ first: String, _ second: String, _ third: String) { print(first + " " + second + " " + third) }

// MARK: Math
//
// The browser has no libm. These cover what application code reaches for through Foundation; they are accurate to
// about 1e-12, which is more than a layout or a chart needs.

public func floor(_ value: Double) -> Double {
  guard value.isFinite, value > -4_503_599_627_370_496, value < 4_503_599_627_370_496 else { return value }
  let truncated = Double(Int64(value))
  return truncated > value ? truncated - 1 : truncated
}

public func ceil(_ value: Double) -> Double { -floor(-value) }

public func exp(_ value: Double) -> Double {
  guard value.isFinite else { return value > 0 ? .infinity : (value < 0 ? 0 : .nan) }
  if value > 709 { return .infinity }
  if value < -745 { return 0 }
  let ln2 = 0.693_147_180_559_945_3
  let steps = floor(value / ln2 + 0.5)
  let reduced = value - steps * ln2
  var term = 1.0
  var sum = 1.0
  var index = 1.0
  while index < 24 {
    term *= reduced / index
    sum += term
    index += 1
  }
  return sum * Double(sign: .plus, exponent: Int(steps), significand: 1)
}

public func log(_ value: Double) -> Double {
  guard value > 0 else { return value == 0 ? -.infinity : .nan }
  guard value.isFinite else { return value }
  let ln2 = 0.693_147_180_559_945_3
  let exponent = Double(value.exponent)
  let mantissa = value.significand
  let ratio = (mantissa - 1) / (mantissa + 1)
  let squared = ratio * ratio
  var term = ratio
  var sum = 0.0
  var divisor = 1.0
  while divisor < 60 {
    sum += term / divisor
    term *= squared
    divisor += 2
  }
  return exponent * ln2 + 2 * sum
}

public func pow(_ base: Double, _ exponent: Double) -> Double {
  if exponent == 0 { return 1 }
  if base == 0 { return exponent > 0 ? 0 : .infinity }
  if exponent == floor(exponent), exponent > -1024, exponent < 1024 {
    var result = 1.0
    var factor = base
    var remaining = Int(exponent < 0 ? -exponent : exponent)
    while remaining > 0 {
      if remaining & 1 == 1 { result *= factor }
      factor *= factor
      remaining >>= 1
    }
    return exponent < 0 ? 1 / result : result
  }
  guard base > 0 else { return .nan }
  return exp(exponent * log(base))
}

// The trigonometric and logarithmic functions of the C library, written in Swift like `exp` and `pow` above. An argument
// is first reduced to a small range (pi/2 is split into three doubles, and the products with the reduction are exact,
// so the reduction stays accurate for any argument a layout or a chart produces); then a series is summed to full
// precision. NaN and the infinities give the results C gives.

/// pi/2 as `_halfPiHigh + _halfPiMiddle + _halfPiLow`, accurate to about 1e-48.
private let _halfPiHigh = 1.5707963267948966
private let _halfPiMiddle = 6.123233995736766e-17
private let _halfPiLow = -1.1386967033862e-33

/// The exact product `a * b` as `high + low`: Dekker's TwoProduct, without a fused multiply-add.
private func _twoProduct(_ a: Double, _ b: Double) -> (high: Double, low: Double) {
  let high = a * b
  // The split below overflows for very large operands; there the tail is dropped (the result is then approximate).
  guard abs(a) < 1e290, abs(b) < 1e290 else { return (high, 0) }
  let splitA = _splitHalves(a)
  let splitB = _splitHalves(b)
  let low = ((splitA.high * splitB.high - high) + splitA.high * splitB.low + splitA.low * splitB.high) + splitA.low * splitB.low
  return (high, low)
}

private func _splitHalves(_ value: Double) -> (high: Double, low: Double) {
  let scaled = 134_217_729 * value
  let high = scaled - (scaled - value)
  return (high, value - high)
}

/// `x - n * pi/2` for the whole number of quarter turns `n` nearest `x`: the remainder is within about pi/4, and the
/// quadrant is `n` modulo 4. `x` must be finite.
private func _reduceToQuarterTurn(_ x: Double) -> (quadrant: Int, remainder: Double) {
  let turns = (x * 0.6366197723675814).rounded(.toNearestOrEven)
  let first = _twoProduct(turns, _halfPiHigh)
  let second = _twoProduct(turns, _halfPiMiddle)
  // `x - first.high` is exact (the two are within a factor of two of each other), so only the small tails are rounded.
  let remainder = (((x - first.high) - first.low) - second.high - second.low) - turns * _halfPiLow
  let quadrant = (Int(turns.truncatingRemainder(dividingBy: 4)) % 4 + 4) % 4
  return (quadrant, remainder)
}

/// sin(r) for |r| <= pi/4 + a little, as the Taylor series.
private func _sineSeries(_ r: Double) -> Double {
  let squared = r * r
  var term = r
  var sum = r
  for step in 1 ... 14 {
    term *= -squared / Double((2 * step) * (2 * step + 1))
    sum += term
  }
  return sum
}

/// cos(r) for |r| <= pi/4 + a little, as the Taylor series.
private func _cosineSeries(_ r: Double) -> Double {
  let squared = r * r
  var term = 1.0
  var sum = 1.0
  for step in 1 ... 14 {
    term *= -squared / Double((2 * step - 1) * (2 * step))
    sum += term
  }
  return sum
}

package func _cmathSin(_ x: Double) -> Double {
  guard x.isFinite else { return .nan }
  if x == 0 { return x }
  let (quadrant, remainder) = _reduceToQuarterTurn(x)
  switch quadrant {
  case 0: return _sineSeries(remainder)
  case 1: return _cosineSeries(remainder)
  case 2: return -_sineSeries(remainder)
  default: return -_cosineSeries(remainder)
  }
}

package func _cmathCos(_ x: Double) -> Double {
  guard x.isFinite else { return .nan }
  let (quadrant, remainder) = _reduceToQuarterTurn(x)
  switch quadrant {
  case 0: return _cosineSeries(remainder)
  case 1: return -_sineSeries(remainder)
  case 2: return -_cosineSeries(remainder)
  default: return _sineSeries(remainder)
  }
}

package func _cmathTan(_ x: Double) -> Double {
  guard x.isFinite else { return .nan }
  if x == 0 { return x }
  let (quadrant, remainder) = _reduceToQuarterTurn(x)
  let sine = _sineSeries(remainder)
  let cosine = _cosineSeries(remainder)
  // tan(r + pi/2) = -cot(r), so an odd quadrant turns the ratio over.
  return quadrant % 2 == 0 ? sine / cosine : -cosine / sine
}

/// atan(t) for |t| <= tan(pi/8), as the alternating series.
private func _arctangentSeries(_ t: Double) -> Double {
  let squared = t * t
  var power = t
  var sum = t
  for step in 1 ... 30 {
    power *= -squared
    sum += power / Double(2 * step + 1)
  }
  return sum
}

/// atan(a) for a >= 0: the reciprocal above 1, and the subtraction of pi/4 above tan(pi/8), keep the series small.
private func _arctangentNonNegative(_ a: Double) -> Double {
  if a > 1 { return Double.pi / 2 - _arctangentNonNegative(1 / a) }
  if a > 0.41421356237309503 { return Double.pi / 4 + _arctangentSeries((a - 1) / (a + 1)) }
  return _arctangentSeries(a)
}

package func _cmathAtan(_ x: Double) -> Double {
  if x.isNaN || x == 0 { return x }
  let result = _arctangentNonNegative(abs(x))
  return x < 0 ? -result : result
}

package func _cmathAsin(_ x: Double) -> Double {
  guard abs(x) <= 1 else { return .nan }
  if x == 0 { return x }
  // asin(x) = atan(x / sqrt(1 - x²)), with 1 - x² written as (1 - x)(1 + x) so it stays exact near ±1.
  return _cmathAtan(x / ((1 - x) * (1 + x)).squareRoot())
}

package func _cmathAcos(_ x: Double) -> Double {
  guard abs(x) <= 1 else { return .nan }
  // acos(x) = 2 atan(sqrt((1 - x) / (1 + x))): 0 at x = 1, pi at x = -1.
  return 2 * _cmathAtan(((1 - x) / (1 + x)).squareRoot())
}

package func _cmathAtan2(_ y: Double, _ x: Double) -> Double {
  if y.isNaN || x.isNaN { return .nan }
  let pi = Double.pi
  if y == 0 { return x.sign == .minus ? _copySign(pi, y) : y }
  if x == 0 { return y < 0 ? -pi / 2 : pi / 2 }
  if x.isInfinite {
    if y.isInfinite { return _copySign(x > 0 ? pi / 4 : 3 * pi / 4, y) }
    return x > 0 ? _copySign(0, y) : _copySign(pi, y)
  }
  if y.isInfinite { return y < 0 ? -pi / 2 : pi / 2 }
  let ratio = _cmathAtan(y / x)
  if x > 0 { return ratio }
  return y < 0 ? ratio - pi : ratio + pi
}

private func _copySign(_ magnitude: Double, _ sign: Double) -> Double {
  sign.sign == .minus ? -magnitude : magnitude
}

package func _cmathSinh(_ x: Double) -> Double {
  guard x.isFinite, x != 0 else { return x }
  let a = abs(x)
  if a < 0.5 {
    // (e^a - e^-a) / 2 loses digits for small a; the series does not.
    var term = a
    var sum = a
    for step in 1 ... 12 {
      term *= a * a / Double((2 * step) * (2 * step + 1))
      sum += term
    }
    return x < 0 ? -sum : sum
  }
  let e = exp(a)
  let result = (e - 1 / e) / 2
  return x < 0 ? -result : result
}

package func _cmathCosh(_ x: Double) -> Double {
  if x.isNaN { return x }
  let e = exp(abs(x))
  return (e + 1 / e) / 2
}

package func _cmathTanh(_ x: Double) -> Double {
  if x.isNaN || x == 0 { return x }
  if abs(x) > 20 { return x < 0 ? -1 : 1 }
  return _cmathSinh(x) / _cmathCosh(x)
}

package func _cmathExp2(_ x: Double) -> Double {
  // Whole powers of two are exact by construction.
  if x == x.rounded(.down), x >= -1074, x <= 1023 { return Double(sign: .plus, exponent: Int(x), significand: 1) }
  return exp(x * 0.6931471805599453)
}

package func _cmathLog2(_ x: Double) -> Double {
  guard x > 0 else { return x == 0 ? -.infinity : .nan }
  guard x.isFinite else { return x }
  // x = significand * 2^exponent with the significand in [1, 2), so an exact power of two gives an exact result.
  return Double(x.exponent) + log(x.significand) / 0.6931471805599453
}

package func _cmathLog10(_ x: Double) -> Double {
  guard x > 0 else { return x == 0 ? -.infinity : .nan }
  guard x.isFinite else { return x }
  return Double(x.exponent) * 0.30102999566398119521 + log(x.significand) / 2.302585092994045684
}

package func _cmathCbrt(_ x: Double) -> Double {
  guard x.isFinite, x != 0 else { return x }
  let a = abs(x)
  var root = exp(log(a) / 3)
  // One Newton step takes the exp/log estimate to full precision.
  root -= (root * root * root - a) / (3 * root * root)
  return x < 0 ? -root : root
}

package func _cmathHypot(_ x: Double, _ y: Double) -> Double {
  // C returns infinity whenever either argument is infinite, even beside a NaN.
  if x.isInfinite || y.isInfinite { return .infinity }
  if x.isNaN || y.isNaN { return .nan }
  let big = max(abs(x), abs(y))
  let small = min(abs(x), abs(y))
  if big == 0 { return 0 }
  let ratio = small / big
  return big * (1 + ratio * ratio).squareRoot()
}

/// The remainder of x / y with the quotient truncated, exact (C's `fmod`): the divisor is subtracted at each power of
/// two up to the dividend's, and each subtraction is exact.
package func _cmathFmod(_ x: Double, _ y: Double) -> Double {
  if x.isNaN || y.isNaN || x.isInfinite || y == 0 { return .nan }
  if y.isInfinite || x == 0 { return x }
  let divisor = abs(y)
  var remainder = abs(x)
  if remainder < divisor { return x }
  var steps = remainder.exponent - divisor.exponent
  var shifted = Double(sign: .plus, exponent: steps, significand: divisor)
  while steps >= 0 {
    if remainder >= shifted { remainder -= shifted }
    shifted *= 0.5
    steps -= 1
  }
  return x < 0 ? -remainder : remainder
}

package func _cmathFmin(_ x: Double, _ y: Double) -> Double { x.isNaN ? y : (y.isNaN ? x : Swift.min(x, y)) }

package func _cmathFmax(_ x: Double, _ y: Double) -> Double { x.isNaN ? y : (y.isNaN ? x : Swift.max(x, y)) }

// The public C names. Native builds get them from the C library (Foundation re-exports Darwin or Glibc), and a second
// declaration here would make every call ambiguous there; Embedded Swift has no libm, so the names are defined here
// for it alone. Native tests reach the implementations above through their `_` names.
#if hasFeature(Embedded)
public func sin(_ x: Double) -> Double { _cmathSin(x) }
public func cos(_ x: Double) -> Double { _cmathCos(x) }
public func tan(_ x: Double) -> Double { _cmathTan(x) }
public func asin(_ x: Double) -> Double { _cmathAsin(x) }
public func acos(_ x: Double) -> Double { _cmathAcos(x) }
public func atan(_ x: Double) -> Double { _cmathAtan(x) }
public func atan2(_ y: Double, _ x: Double) -> Double { _cmathAtan2(y, x) }
public func sinh(_ x: Double) -> Double { _cmathSinh(x) }
public func cosh(_ x: Double) -> Double { _cmathCosh(x) }
public func tanh(_ x: Double) -> Double { _cmathTanh(x) }
public func exp2(_ x: Double) -> Double { _cmathExp2(x) }
public func log2(_ x: Double) -> Double { _cmathLog2(x) }
public func log10(_ x: Double) -> Double { _cmathLog10(x) }
public func cbrt(_ x: Double) -> Double { _cmathCbrt(x) }
public func hypot(_ x: Double, _ y: Double) -> Double { _cmathHypot(x, y) }
public func fmod(_ x: Double, _ y: Double) -> Double { _cmathFmod(x, y) }
public func fmin(_ x: Double, _ y: Double) -> Double { _cmathFmin(x, y) }
public func fmax(_ x: Double, _ y: Double) -> Double { _cmathFmax(x, y) }

// `Float` overloads, as the C math library's single-precision functions are spelled: the double-precision result,
// rounded to `Float`.
public func sin(_ x: Float) -> Float { Float(_cmathSin(Double(x))) }
public func cos(_ x: Float) -> Float { Float(_cmathCos(Double(x))) }
public func tan(_ x: Float) -> Float { Float(_cmathTan(Double(x))) }
public func asin(_ x: Float) -> Float { Float(_cmathAsin(Double(x))) }
public func acos(_ x: Float) -> Float { Float(_cmathAcos(Double(x))) }
public func atan(_ x: Float) -> Float { Float(_cmathAtan(Double(x))) }
public func atan2(_ y: Float, _ x: Float) -> Float { Float(_cmathAtan2(Double(y), Double(x))) }
public func sinh(_ x: Float) -> Float { Float(_cmathSinh(Double(x))) }
public func cosh(_ x: Float) -> Float { Float(_cmathCosh(Double(x))) }
public func tanh(_ x: Float) -> Float { Float(_cmathTanh(Double(x))) }
public func exp2(_ x: Float) -> Float { Float(_cmathExp2(Double(x))) }
public func log2(_ x: Float) -> Float { Float(_cmathLog2(Double(x))) }
public func log10(_ x: Float) -> Float { Float(_cmathLog10(Double(x))) }
public func cbrt(_ x: Float) -> Float { Float(_cmathCbrt(Double(x))) }
public func hypot(_ x: Float, _ y: Float) -> Float { Float(_cmathHypot(Double(x), Double(y))) }
public func fmod(_ x: Float, _ y: Float) -> Float { Float(_cmathFmod(Double(x), Double(y))) }
public func fmin(_ x: Float, _ y: Float) -> Float { Float(_cmathFmin(Double(x), Double(y))) }
public func fmax(_ x: Float, _ y: Float) -> Float { Float(_cmathFmax(Double(x), Double(y))) }
#endif

/// POSIX `srand48`/`drand48`: the same 48-bit generator, so a seed gives the same sequence as on Apple platforms.
nonisolated(unsafe) private var rand48State: UInt64 = 0x1234_ABCD_330E

public func srand48(_ seed: Int) {
  rand48State = ((UInt64(truncatingIfNeeded: seed) & 0xFFFF_FFFF) << 16) | 0x330E
}

public func drand48() -> Double {
  rand48State = (rand48State &* 0x5_DEEC_E66D &+ 0xB) & 0xFFFF_FFFF_FFFF
  return Double(rand48State) / 281_474_976_710_656.0
}

// MARK: Concurrency

#if hasFeature(Embedded)
extension Task where Success == Never, Failure == Never {
  /// `Task.sleep(nanoseconds:)` is unavailable in Embedded Swift; the browser owns the timer.
  public static func sleep(nanoseconds: UInt64) async throws {
    try await BrowserTimer.sleep(for: Double(nanoseconds) / 1_000_000_000)
  }
}
#endif

#if !hasFeature(Embedded)
/// Archived as its `uuidString`, as Foundation archives a UUID.
extension UUID: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let uuid = UUID(uuidString: text) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Attempted to decode UUID from invalid UUID string.")
    }
    self = uuid
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(uuidString)
  }
}
#endif

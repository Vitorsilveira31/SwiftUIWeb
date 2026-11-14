@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// Host-neutral ISO 8601 timestamp parsing and formatting shared by the
// Foundation-shaped `Date.ISO8601FormatStyle` of
// SwiftUIWebInternationalization and by renderer code. It is plain
// arithmetic (proleptic Gregorian calendar, fractional seconds, fixed
// offsets), so it needs neither a host nor Foundation. Integers are `Int64`
// because `Int` is 32 bits on wasm32.

/// Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm).
private func daysFromCivil(_ year: Int64, _ month: Int64, _ day: Int64) -> Int64 {
  let y = month <= 2 ? year - 1 : year
  let era = (y >= 0 ? y : y - 399) / 400
  let yearOfEra = y - era * 400
  let monthPrime = month > 2 ? month - 3 : month + 9
  let dayOfYear = (153 * monthPrime + 2) / 5 + day - 1
  let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
  return era * 146_097 + dayOfEra - 719_468
}

/// The civil date (year, month, day) of a day number since 1970-01-01.
private func civilFromDays(_ days: Int64) -> (Int64, Int64, Int64) {
  let z = days + 719_468
  let era = (z >= 0 ? z : z - 146_096) / 146_097
  let dayOfEra = z - era * 146_097
  let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
  let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
  let monthPrime = (5 * dayOfYear + 2) / 153
  let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
  let month = monthPrime < 10 ? monthPrime + 3 : monthPrime - 9
  return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
}

private func daysInMonth(_ year: Int64, _ month: Int64) -> Int64 {
  switch month {
  case 1, 3, 5, 7, 8, 10, 12: return 31
  case 4, 6, 9, 11: return 30
  case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
  default: return 0
  }
}

/// Seconds since 1970 of an RFC 3339 timestamp such as
/// `2026-09-29T18:05:30.000-03:00`, or nil when it is malformed. Like
/// Foundation's `.iso8601` strategy it also takes a `t` or a space between
/// date and time, `,` before the fraction and `±HHMM` or `±HH` offsets.
@_spi(Renderer) public func _swiftUIWebParseISO8601(_ value: String) -> Double? {
  let bytes = Array(value.utf8)
  func digits(_ start: Int, _ count: Int) -> Int64? {
    guard start + count <= bytes.count else { return nil }
    var result: Int64 = 0
    for index in start ..< start + count {
      guard bytes[index] >= 48, bytes[index] <= 57 else { return nil }
      result = result * 10 + Int64(bytes[index] - 48)
    }
    return result
  }
  guard bytes.count >= 20, let year = digits(0, 4), let month = digits(5, 2), let day = digits(8, 2),
        let hour = digits(11, 2), let minute = digits(14, 2), let second = digits(17, 2) else { return nil }
  // `-`, `T`/`t`/space, `:`.
  guard bytes[4] == 45, bytes[7] == 45, bytes[10] == 84 || bytes[10] == 116 || bytes[10] == 32, bytes[13] == 58, bytes[16] == 58 else { return nil }
  guard month >= 1, month <= 12, day >= 1, day <= daysInMonth(year, month), hour <= 23, minute <= 59, second <= 60 else { return nil }
  var index = 19
  var fraction = 0.0
  if bytes[index] == 46 || bytes[index] == 44 {
    index += 1
    var scale = 0.1
    let first = index
    while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
      fraction += Double(bytes[index] - 48) * scale
      scale /= 10
      index += 1
    }
    if index == first { return nil }
  }
  guard index < bytes.count else { return nil }
  var offset: Int64 = 0
  if bytes[index] == 90 || bytes[index] == 122 {  // Z, z
    index += 1
  } else if bytes[index] == 43 || bytes[index] == 45 {  // +, -
    let negative = bytes[index] == 45
    guard let hours = digits(index + 1, 2) else { return nil }
    var minutes: Int64 = 0
    if index + 3 < bytes.count, bytes[index + 3] == 58 || (bytes[index + 3] >= 48 && bytes[index + 3] <= 57) {
      let start = bytes[index + 3] == 58 ? index + 4 : index + 3
      guard let parsed = digits(start, 2) else { return nil }
      minutes = parsed
      index = start + 2
    } else {
      index += 3
    }
    guard hours <= 23, minutes <= 59 else { return nil }
    offset = (hours * 3_600 + minutes * 60) * (negative ? -1 : 1)
  } else {
    return nil
  }
  guard index == bytes.count else { return nil }
  let seconds = daysFromCivil(year, month, day) * 86_400 + hour * 3_600 + minute * 60 + second - offset
  return Double(seconds) + fraction
}

/// `YYYY-MM-DDTHH:MM:SS[.mmm]` followed by `Z` or the `±HH:MM` offset; empty
/// for a non-finite or out-of-range epoch. The time is truncated, never
/// rounded up: 59.9996 prints as :59.
@_spi(Renderer) public func _swiftUIWebFormatISO8601(_ epochSeconds: Double, offsetSeconds: Int = 0, fractionalSeconds: Bool = false) -> String {
  guard epochSeconds.isFinite, epochSeconds.magnitude <= 1.0e17 else { return "" }
  let local = epochSeconds + Double(offsetSeconds)
  var whole = Int64(local)
  if Double(whole) > local { whole -= 1 }
  let milliseconds = min(max(Int64((local - Double(whole)) * 1000), 0), 999)
  var days = whole / 86_400
  var daySeconds = whole % 86_400
  if daySeconds < 0 { daySeconds += 86_400; days -= 1 }
  let (year, month, day) = civilFromDays(days)
  func padded(_ value: Int64, _ width: Int) -> String {
    let digits = String(value.magnitude)
    return String(repeating: "0", count: max(0, width - digits.utf8.count)) + digits
  }
  var result = year < 0 ? "-" : ""
  result += padded(year, 4); result += "-"; result += padded(month, 2); result += "-"; result += padded(day, 2)
  result += "T"; result += padded(daySeconds / 3_600, 2); result += ":"
  result += padded(daySeconds % 3_600 / 60, 2); result += ":"; result += padded(daySeconds % 60, 2)
  if fractionalSeconds { result += "."; result += padded(milliseconds, 3) }
  if offsetSeconds == 0 { return result + "Z" }
  let magnitude = Int64(offsetSeconds).magnitude
  result += offsetSeconds < 0 ? "-" : "+"
  result += padded(Int64(magnitude / 3_600), 2); result += ":"; result += padded(Int64(magnitude % 3_600 / 60), 2)
  return result
}

@_spi(Renderer) import SwiftUIWebCore

/// Parsed `Intl.DateTimeFormat` options (`name=value;...`), shared by
/// `Date.FormatStyle`, `Text(_:style:)` and date ranges.
struct _DateFormatOptions {
  private var values: [String: String] = [:]

  init(_ encoded: String) {
    for pair in encoded.split(separator: ";") {
      let parts = pair.split(separator: "=", maxSplits: 1)
      if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
    }
  }

  subscript(_ name: String) -> String? { values[name] }

  /// ICU skeleton for Foundation's `setLocalizedDateFormatFromTemplate`.
  var icuTemplate: String {
    var template = ""
    switch self["weekday"] { case "long"?: template += "EEEE"; case "narrow"?: template += "EEEEE"; case "short"?: template += "EEE"; default: break }
    switch self["year"] { case "2-digit"?: template += "yy"; case "numeric"?: template += "y"; default: break }
    switch self["month"] { case "numeric"?: template += "M"; case "2-digit"?: template += "MM"; case "short"?: template += "MMM"; case "long"?: template += "MMMM"; case "narrow"?: template += "MMMMM"; default: break }
    switch self["day"] { case "numeric"?: template += "d"; case "2-digit"?: template += "dd"; default: break }
    let twentyFourHour = self["hour12"] == "false"
    switch self["hour"] { case "numeric"?: template += twentyFourHour ? "H" : "j"; case "2-digit"?: template += twentyFourHour ? "HH" : "jj"; default: break }
    if self["minute"] != nil { template += "mm" }
    if self["second"] != nil { template += "ss" }
    switch self["timeZoneName"] { case "short"?: template += "z"; case "long"?: template += "zzzz"; default: break }
    return template
  }

  /// Deterministic en-US Gregorian (UTC) rendering used when no browser
  /// `Intl` host is installed.
  func englishText(for date: Date) -> String {
    let seconds = date.timeIntervalSince1970
    guard seconds.isFinite, abs(seconds) < 1.0e14 else { return "Invalid Date" }
    let dayNumber = Int64((seconds / 86_400).rounded(.down))
    let daySeconds = Int(seconds - Double(dayNumber) * 86_400)
    let civil = _civilDate(days: dayNumber)
    var dateText = ""
    let monthIndex = civil.month - 1
    if let weekday = self["weekday"] {
      let index = Int(((dayNumber + 4) % 7 + 7) % 7)
      let name = _weekdayNames[index]
      dateText = weekday == "long" ? name : weekday == "narrow" ? String(name.prefix(1)) : String(name.prefix(3))
    }
    let month = self["month"], day = self["day"], year = self["year"]
    let yearText = year == "2-digit" ? _twoDigits(civil.year % 100) : String(civil.year)
    if month == "numeric" || month == "2-digit" {
      var parts: [String] = []
      parts.append(month == "2-digit" ? _twoDigits(civil.month) : String(civil.month))
      if let day { parts.append(day == "2-digit" ? _twoDigits(civil.day) : String(civil.day)) }
      if year != nil { parts.append(yearText) }
      dateText += (dateText.isEmpty ? "" : ", ") + parts.joined(separator: "/")
    } else if month != nil || day != nil || year != nil {
      var text = ""
      if let month {
        let name = _monthNames[monthIndex]
        text = month == "long" ? name : month == "narrow" ? String(name.prefix(1)) : String(name.prefix(3))
      }
      if let day { text += (text.isEmpty ? "" : " ") + (day == "2-digit" ? _twoDigits(civil.day) : String(civil.day)) }
      if year != nil { text += (text.isEmpty ? "" : (day != nil ? ", " : " ")) + yearText }
      dateText += (dateText.isEmpty ? "" : ", ") + text
    }
    var timeText = ""
    if let hourStyle = self["hour"] {
      let hour = daySeconds / 3_600
      let twentyFour = self["hour12"] == "false"
      let displayHour = twentyFour ? hour : (hour % 12 == 0 ? 12 : hour % 12)
      timeText = hourStyle == "2-digit" ? _twoDigits(displayHour) : String(displayHour)
      if self["minute"] != nil { timeText += ":" + _twoDigits(daySeconds % 3_600 / 60) }
      if self["second"] != nil { timeText += ":" + _twoDigits(daySeconds % 60) }
      if !twentyFour { timeText += hour < 12 ? " AM" : " PM" }
      if self["timeZoneName"] != nil { timeText += " UTC" }
    }
    if dateText.isEmpty { return timeText }
    return timeText.isEmpty ? dateText : dateText + ", " + timeText
  }
}

private let _monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
private let _weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

private func _twoDigits(_ value: Int) -> String { value < 10 ? "0" + String(value) : String(value) }

/// Howard Hinnant's days-from-civil inverse (proleptic Gregorian, UTC).
private func _civilDate(days: Int64) -> (year: Int, month: Int, day: Int) {
  let z = days + 719_468
  let era = (z >= 0 ? z : z - 146_096) / 146_097
  let doe = z - era * 146_097
  let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = mp < 10 ? mp + 3 : mp - 9
  let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
  return (Int(year), Int(month), Int(day))
}

/// SwiftUI's duration texts for `.relative`, `.offset` and `.timer`. The
/// browser host renders the same shapes with `Intl.NumberFormat` units.
enum _DateDurationText {
  private static let units: [(name: String, seconds: Double)] = [
    ("year", 31_536_000), ("month", 2_592_000), ("week", 604_800), ("day", 86_400),
    ("hour", 3_600), ("minute", 60), ("second", 1)
  ]

  /// Two most significant units, e.g. "2 hours, 23 minutes".
  static func relative(seconds: Double) -> String {
    guard seconds.isFinite else { return "" }
    let magnitude = abs(seconds).rounded(.down)
    guard let index = units.firstIndex(where: { magnitude >= $0.seconds }) else { return phrase(0, "second") }
    let major = (magnitude / units[index].seconds).rounded(.down)
    // Counts are Int64: `Int` is 32 bits in the browser build, where Int(major) would trap from about 68 years of
    // seconds on. Int64(major) traps from 2^63 units on; such an interval renders like a non-finite one.
    guard major < 0x1p63 else { return "" }
    var parts = [phrase(Int64(major), units[index].name)]
    if index + 1 < units.count {
      let minor = ((magnitude - major * units[index].seconds) / units[index + 1].seconds).rounded(.down)
      if minor >= 1 { parts.append(phrase(Int64(minor), units[index + 1].name)) }
    }
    return parts.joined(separator: ", ")
  }

  /// Signed most significant unit, e.g. "+2 hours" / "-5 minutes".
  static func offset(seconds: Double) -> String {
    guard seconds.isFinite else { return "" }
    let magnitude = abs(seconds).rounded(.down)
    let unit = units.first { magnitude >= $0.seconds } ?? units[units.count - 1]
    let count = (magnitude / unit.seconds).rounded(.down)
    guard count < 0x1p63 else { return "" }
    return (seconds < 0 ? "-" : "+") + phrase(Int64(count), unit.name)
  }

  /// A clock-style duration, e.g. "1:02:03" or "2:03".
  static func timer(seconds: Double, showsHours: Bool) -> String {
    guard seconds.isFinite else { return "0:00" }
    let magnitude = abs(seconds).rounded(.down)
    // Int64, not Int (32 bits in the browser build); Int64(magnitude) traps from 2^63 seconds on, and such a duration
    // renders like a non-finite one.
    guard magnitude < 0x1p63 else { return "0:00" }
    let total = Int64(magnitude)
    let hours = total / 3_600, minutes = total % 3_600 / 60, secs = total % 60
    let sign = seconds <= -1 ? "-" : ""
    if showsHours && hours > 0 { return sign + String(hours) + ":" + _twoDigits(Int(minutes)) + ":" + _twoDigits(Int(secs)) }
    return sign + String(showsHours ? minutes : hours * 60 + minutes) + ":" + _twoDigits(Int(secs))
  }

  private static func phrase(_ count: Int64, _ unit: String) -> String {
    String(count) + " " + unit + (count == 1 ? "" : "s")
  }
}

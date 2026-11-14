// Foundation's `Calendar` symbol arrays for browser and Embedded builds. Names come from the host's Intl formatter in
// the calendar's locale, as contextual forms. Weekdays start with Sunday whatever the first weekday is, and months
// start with January, as Foundation's do. Without a host formatter the English names are used.
@_spi(Browser) import SwiftUIWebInternationalization

extension Calendar {
  public var weekdaySymbols: [String] { _weekdaySymbols(width: "long") }
  public var shortWeekdaySymbols: [String] { _weekdaySymbols(width: "short") }
  public var veryShortWeekdaySymbols: [String] { _weekdaySymbols(width: "narrow") }

  public var monthSymbols: [String] { _monthSymbols(width: "long") }
  public var shortMonthSymbols: [String] { _monthSymbols(width: "short") }
  public var veryShortMonthSymbols: [String] { _monthSymbols(width: "narrow") }

  // The standalone forms (a month or weekday named by itself, as in a heading). Intl has no standalone form, so the host
  // names come out as the contextual ones; the arrays exist so code written against Foundation compiles and reads.
  public var standaloneWeekdaySymbols: [String] { _weekdaySymbols(width: "long") }
  public var shortStandaloneWeekdaySymbols: [String] { _weekdaySymbols(width: "short") }
  public var veryShortStandaloneWeekdaySymbols: [String] { _weekdaySymbols(width: "narrow") }

  public var standaloneMonthSymbols: [String] { _monthSymbols(width: "long") }
  public var shortStandaloneMonthSymbols: [String] { _monthSymbols(width: "short") }
  public var veryShortStandaloneMonthSymbols: [String] { _monthSymbols(width: "narrow") }

  /// 1970-01-04 was a Sunday. Noon UTC is well inside that day for every fixed offset used here (the formatter
  /// is given offset 0), so each name is read from the same weekday.
  private func _weekdaySymbols(width: String) -> [String] {
    let english = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    return (0 ..< 7).map { index in
      let epoch = 259_200 + Double(index) * 86_400 + 43_200
      return _calendarName(epoch: epoch, option: "weekday=\(width)", fallback: english[index], width: width)
    }
  }

  /// Day 14 (the 15th) of each month of 1970, at noon UTC.
  private func _monthSymbols(width: String) -> [String] {
    let daysBeforeMonth = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    let english = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    return (0 ..< 12).map { index in
      let epoch = Double(daysBeforeMonth[index] + 14) * 86_400 + 43_200
      return _calendarName(epoch: epoch, option: "month=\(width)", fallback: english[index], width: width)
    }
  }

  private func _calendarName(epoch: Double, option: String, fallback: String, width: String) -> String {
    let identifier = (locale ?? Locale.current).identifier
    if let text = _BrowserDateFormatting.format(_BrowserDateFormatRequest(
      epochSeconds: epoch, style: .custom, locale: identifier, options: option
    )), !text.isEmpty {
      return text
    }
    switch width {
    case "narrow": return String(fallback.prefix(1))
    case "short": return String(fallback.prefix(3))
    default: return fallback
    }
  }
}

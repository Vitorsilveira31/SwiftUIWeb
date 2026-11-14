// Browser presentation delegates to native Intl. Native hosts keep Foundation.
// This source does not import Foundation on WASI or Embedded targets.
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

public extension LocalizedStringKey.StringInterpolation {
  /// `Text("ends \(date, style: .relative)")`: the date as the style prints it now. (`Text(date, style:)` itself
  /// stays live in the browser; text interpolated into a longer string is the value at render time.)
  mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) {
    _appendString(Text(date, style: style).value)
  }
}

/// SwiftUI's date-bearing `Text` initializers.
///
/// Each text carries its epoch (and range/timer parameters) as renderer
/// metadata. The browser host re-formats it with `Intl` in the user's locale
/// and time zone after every commit, and keeps the live styles — `.relative`,
/// `.offset`, `.timer` and `Text(timerInterval:)` — ticking once per second
/// without re-rendering Swift, like SwiftUI. The Swift-side string is the
/// initial/static value (Foundation natively, English Gregorian otherwise).
public extension Text {
  init(_ date: Date, style: Text.DateStyle) {
    let epoch = date.timeIntervalSince1970
    let now = Date().timeIntervalSince1970
    let value: String
    switch style {
    case .date: value = _swiftUIWebFormatDate(date, options: "year=numeric;month=long;day=numeric", locale: "")
    case .time: value = _swiftUIWebFormatDate(date, options: "hour=numeric;minute=2-digit", locale: "")
    case .relative: value = _DateDurationText.relative(seconds: epoch - now)
    case .offset: value = _DateDurationText.offset(seconds: epoch - now)
    case .timer: value = _DateDurationText.timer(seconds: now - epoch, showsHours: true)
    }
    var attributes = [("data-text-date-epoch", _swiftUIWebEpochText(epoch))]
    if style == .relative || style == .offset || style == .timer { attributes.append(("data-text-date-live", "true")) }
    self.init(_swiftUIWebValue: value, dateStyle: style, attributes: attributes)
  }

  /// A localized date range such as "Sep 29, 2026, 10:00 – 11:30 AM".
  init(_ dates: ClosedRange<Date>) {
    let options = "year=numeric;month=short;day=numeric;hour=numeric;minute=2-digit"
    let value = _swiftUIWebFormatDate(dates.lowerBound, options: options, locale: "")
      + " – " + _swiftUIWebFormatDate(dates.upperBound, options: options, locale: "")
    self.init(_swiftUIWebValue: value, dateStyle: nil, attributes: [
      ("data-text-date-kind", "range"),
      ("data-text-date-epoch", _swiftUIWebEpochText(dates.lowerBound.timeIntervalSince1970)),
      ("data-text-date-end", _swiftUIWebEpochText(dates.upperBound.timeIntervalSince1970))
    ])
  }

  /// A live countdown (or count-up) over `timerInterval`, frozen at
  /// `pauseTime` when supplied.
  init(timerInterval: ClosedRange<Date>, pauseTime: Date? = nil, countsDown: Bool = true, showsHours: Bool = true) {
    let start = timerInterval.lowerBound.timeIntervalSince1970
    let end = timerInterval.upperBound.timeIntervalSince1970
    let now = (pauseTime ?? Date()).timeIntervalSince1970
    let clamped = min(max(now, start), end)
    let value = _DateDurationText.timer(seconds: countsDown ? end - clamped : clamped - start, showsHours: showsHours)
    var attributes = [
      ("data-text-date-kind", "timer-interval"),
      ("data-text-date-epoch", _swiftUIWebEpochText(start)),
      ("data-text-date-end", _swiftUIWebEpochText(end)),
      ("data-text-date-counts-down", countsDown ? "true" : "false"),
      ("data-text-date-shows-hours", showsHours ? "true" : "false")
    ]
    if let pauseTime { attributes.append(("data-text-date-pause", _swiftUIWebEpochText(pauseTime.timeIntervalSince1970))) }
    else { attributes.append(("data-text-date-live", "true")) }
    self.init(_swiftUIWebValue: value, dateStyle: nil, attributes: attributes)
  }

  /// Formats `input` with a `FormatStyle` (Foundation's natively; the
  /// browser `Intl`-backed `Date.FormatStyle` in Embedded builds).
  init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatInput: Equatable, F.FormatOutput == String {
    self.init(verbatim: format.format(input))
  }
}

func _swiftUIWebEpochText(_ seconds: Double) -> String {
  guard seconds.isFinite, seconds > -9.0e15, seconds < 9.0e15 else { return "0" }
  let milliseconds = Int64((seconds * 1000).rounded())
  // Split the magnitude, so -2.3 reads as "-2.3" (not "-2.7"), and keep the sign in front.
  let sign = milliseconds < 0 ? "-" : ""
  let magnitude = milliseconds < 0 ? -milliseconds : milliseconds
  let whole = magnitude / 1000
  let fraction = magnitude % 1000
  if fraction == 0 { return sign + String(whole) }
  var digits = String(fraction)
  while digits.count < 3 { digits = "0" + digits }
  while digits.hasSuffix("0") { digits.removeLast() }
  return sign + String(whole) + "." + digits
}

/// Formats a date from `Intl.DateTimeFormat` options (`name=value;...`).
@_spi(Renderer) public func _swiftUIWebFormatDate(_ date: Date, options: String, locale: String) -> String {
  if let value = _BrowserDateFormatting.format(.init(
    epochSeconds: date.timeIntervalSince1970, style: .custom,
    locale: locale, options: options + ";timeZone=local"
  )) { return value }
  return _DateFormatOptions(options).englishText(for: date)
}

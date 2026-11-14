// Embedded/WASI counterpart of Foundation's `FormatStyle` and
// `Date.FormatStyle`. Native builds use Foundation's own types, so the same
// application source (`date.formatted(date: .abbreviated, time: .shortened)`,
// `Text(date, format: .dateTime.day().month(.wide))`) compiles everywhere.
// Formatting is delegated to the browser's `Intl.DateTimeFormat` in the
// user's locale and time zone; a deterministic English Gregorian fallback is
// used where no browser host is installed (tests, static rendering).
@_spi(Renderer) import SwiftUIWebCore

public protocol FormatStyle {
  associatedtype FormatInput
  associatedtype FormatOutput
  func format(_ value: FormatInput) -> FormatOutput
  /// The output for an integer of another type, when this style formats integers; nil otherwise. `BinaryInteger`'s
  /// `formatted(_:)` uses it for a value the style's own integer type cannot hold (an `Int64` past 2^31 formatted with
  /// `.number`, an `IntegerFormatStyle<Int>`, where `Int` is 32 bits), which Foundation would convert and trap on.
  func _formatInteger<Value: BinaryInteger>(_ value: Value) -> FormatOutput?
}

public extension FormatStyle {
  func _formatInteger<Value: BinaryInteger>(_ value: Value) -> FormatOutput? { nil }
}

public extension Date {
  struct FormatStyle: SwiftUIWebInternationalization.FormatStyle, Hashable, Sendable {
    public enum DateStyle: Hashable, Sendable { case omitted, numeric, abbreviated, long, complete }
    public enum TimeStyle: Hashable, Sendable { case omitted, shortened, standard, complete }

    /// Field symbols (`Date.FormatStyle.Symbol.Month.wide`, ...). Each value
    /// is the matching `Intl.DateTimeFormat` option.
    public enum Symbol {
      public struct Year: Hashable, Sendable { let intl: String
        public static let defaultDigits = Year(intl: "numeric"); public static let twoDigits = Year(intl: "2-digit") }
      public struct Month: Hashable, Sendable { let intl: String
        public static let defaultDigits = Month(intl: "numeric"); public static let twoDigits = Month(intl: "2-digit")
        public static let wide = Month(intl: "long"); public static let abbreviated = Month(intl: "short"); public static let narrow = Month(intl: "narrow") }
      public struct Day: Hashable, Sendable { let intl: String
        public static let defaultDigits = Day(intl: "numeric"); public static let twoDigits = Day(intl: "2-digit") }
      public struct Weekday: Hashable, Sendable { let intl: String
        public static let wide = Weekday(intl: "long"); public static let abbreviated = Weekday(intl: "short")
        public static let short = Weekday(intl: "short"); public static let narrow = Weekday(intl: "narrow") }
      public struct Hour: Hashable, Sendable { let intl: String
        public struct AMPMStyle: Hashable, Sendable { let hour12: String?
          public static let omitted = AMPMStyle(hour12: "false"); public static let narrow = AMPMStyle(hour12: nil)
          public static let abbreviated = AMPMStyle(hour12: nil); public static let wide = AMPMStyle(hour12: nil) }
        let hour12: String?
        public static let defaultDigitsNoAMPM = Hour(intl: "numeric", hour12: "false")
        public static let twoDigitsNoAMPM = Hour(intl: "2-digit", hour12: "false")
        public static func defaultDigits(amPM: AMPMStyle) -> Hour { Hour(intl: "numeric", hour12: amPM.hour12) }
        public static func twoDigits(amPM: AMPMStyle) -> Hour { Hour(intl: "2-digit", hour12: amPM.hour12) }
        public static func conversationalDefaultDigits(amPM: AMPMStyle) -> Hour { Hour(intl: "numeric", hour12: amPM.hour12) } }
      public struct Minute: Hashable, Sendable { let intl: String
        public static let defaultDigits = Minute(intl: "numeric"); public static let twoDigits = Minute(intl: "2-digit") }
      public struct Second: Hashable, Sendable { let intl: String
        public static let defaultDigits = Second(intl: "numeric"); public static let twoDigits = Second(intl: "2-digit") }
      public struct TimeZone: Hashable, Sendable { let intl: String
        // The Intl.DateTimeFormat `timeZoneName` each of Foundation's symbols maps to.
        public static func specificName(_ width: Width) -> TimeZone { TimeZone(intl: width == .short ? "short" : "long") }
        public static func genericName(_ width: Width) -> TimeZone { TimeZone(intl: width == .short ? "shortGeneric" : "longGeneric") }
        public static func localizedGMT(_ width: Width) -> TimeZone { TimeZone(intl: width == .short ? "shortOffset" : "longOffset") }
        public static func iso8601(_ width: Width) -> TimeZone { TimeZone(intl: "shortOffset") }
        public enum Width: Hashable, Sendable { case short, long } }
    }

    /// Ordered `Intl.DateTimeFormat` options (`name=value`).
    var _options: [String]
    var _locale: String = ""

    public init(date: DateStyle? = nil, time: TimeStyle? = nil) {
      _options = Self._presetOptions(date: date, time: time)
    }

    public func format(_ value: Date) -> String {
      _swiftUIWebFormatDate(value, options: _intlOptions, locale: _locale)
    }

    public func locale(_ locale: Locale) -> Self { var copy = self; copy._locale = locale._formatterTag; return copy }
    public func year(_ format: Symbol.Year = .defaultDigits) -> Self { adding("year", format.intl) }
    public func month(_ format: Symbol.Month = .abbreviated) -> Self { adding("month", format.intl) }
    public func day(_ format: Symbol.Day = .defaultDigits) -> Self { adding("day", format.intl) }
    public func weekday(_ format: Symbol.Weekday = .abbreviated) -> Self { adding("weekday", format.intl) }
    public func hour(_ format: Symbol.Hour = .defaultDigits(amPM: .abbreviated)) -> Self {
      var copy = adding("hour", format.intl)
      if let hour12 = format.hour12 { copy = copy.adding("hour12", hour12) }
      return copy
    }
    public func minute(_ format: Symbol.Minute = .defaultDigits) -> Self { adding("minute", format.intl) }
    public func second(_ format: Symbol.Second = .defaultDigits) -> Self { adding("second", format.intl) }
    public func timeZone(_ format: Date.FormatStyle.Symbol.TimeZone = .specificName(.short)) -> Date.FormatStyle { adding("timeZoneName", format.intl) }

    /// SwiftUI's `.dateTime` without fields means numeric date plus time.
    var _intlOptions: String {
      let options = _options.isEmpty ? Self._presetOptions(date: .numeric, time: .shortened) : _options
      return options.joined(separator: ";")
    }

    private func adding(_ name: String, _ value: String) -> Self {
      var copy = self
      copy._options.removeAll { $0.hasPrefix(name + "=") }
      copy._options.append(name + "=" + value)
      return copy
    }

    private static func _presetOptions(date: DateStyle?, time: TimeStyle?) -> [String] {
      var options: [String] = []
      switch date {
      case .numeric?: options += ["year=numeric", "month=numeric", "day=numeric"]
      case .abbreviated?: options += ["year=numeric", "month=short", "day=numeric"]
      case .long?: options += ["year=numeric", "month=long", "day=numeric"]
      case .complete?: options += ["weekday=long", "year=numeric", "month=long", "day=numeric"]
      case .omitted?, nil: break
      }
      switch time {
      case .shortened?: options += ["hour=numeric", "minute=2-digit"]
      case .standard?: options += ["hour=numeric", "minute=2-digit", "second=2-digit"]
      case .complete?: options += ["hour=numeric", "minute=2-digit", "second=2-digit", "timeZoneName=short"]
      case .omitted?, nil: break
      }
      return options
    }
  }

  func formatted(date: FormatStyle.DateStyle, time: FormatStyle.TimeStyle) -> String {
    FormatStyle(date: date, time: time).format(self)
  }

  func formatted() -> String { FormatStyle(date: .numeric, time: .shortened).format(self) }

  func formatted<F: SwiftUIWebInternationalization.FormatStyle>(_ format: F) -> F.FormatOutput where F.FormatInput == Date {
    format.format(self)
  }
}

public extension SwiftUIWebInternationalization.FormatStyle where Self == Date.FormatStyle {
  static var dateTime: Date.FormatStyle { Date.FormatStyle() }
}

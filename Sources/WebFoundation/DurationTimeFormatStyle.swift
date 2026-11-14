// Foundation's `Duration.TimeFormatStyle`: `Duration.seconds(3723).formatted(.time(pattern: .hourMinuteSecond))` is
// "1:02:03". The arithmetic is on the duration's Int64 seconds and attoseconds, so a duration of any length formats
// without trapping where `Int` is 32 bits.
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebInternationalization

extension Duration {
  public struct TimeFormatStyle: SwiftUIWebInternationalization.FormatStyle, Hashable, Sendable {
    public struct Pattern: Hashable, Sendable {
      enum Fields: Hashable, Sendable { case hourMinute, hourMinuteSecond, minuteSecond }
      let fields: Fields
      let padding: Int
      let fractionLength: Int
      let rounding: FloatingPointRoundingRule

      public static var hourMinute: Pattern { hourMinute(padHourToLength: 1) }
      public static func hourMinute(padHourToLength: Int, roundSeconds: FloatingPointRoundingRule = .toNearestOrEven) -> Pattern {
        Pattern(fields: .hourMinute, padding: padHourToLength, fractionLength: 0, rounding: roundSeconds)
      }
      public static var hourMinuteSecond: Pattern { hourMinuteSecond(padHourToLength: 1) }
      public static func hourMinuteSecond(padHourToLength: Int, fractionalSecondsLength: Int = 0, roundFractionalSeconds: FloatingPointRoundingRule = .toNearestOrEven) -> Pattern {
        Pattern(fields: .hourMinuteSecond, padding: padHourToLength, fractionLength: fractionalSecondsLength, rounding: roundFractionalSeconds)
      }
      public static var minuteSecond: Pattern { minuteSecond(padMinuteToLength: 1) }
      public static func minuteSecond(padMinuteToLength: Int, fractionalSecondsLength: Int = 0, roundFractionalSeconds: FloatingPointRoundingRule = .toNearestOrEven) -> Pattern {
        Pattern(fields: .minuteSecond, padding: padMinuteToLength, fractionLength: fractionalSecondsLength, rounding: roundFractionalSeconds)
      }
    }

    public var locale: Locale
    public var pattern: Pattern

    public init(pattern: Pattern, locale: Locale = .autoupdatingCurrent) {
      self.pattern = pattern
      self.locale = locale
    }

    public func locale(_ locale: Locale) -> TimeFormatStyle {
      var copy = self
      copy.locale = locale
      return copy
    }

    public func format(_ value: Duration) -> String {
      let (seconds, attoseconds) = value.components
      // Seconds and attoseconds carry the same sign; the arithmetic is on their magnitudes, in integers, so a tie is
      // decided on the duration itself (575 ms to two digits is 0.58) and not on a Double near it.
      let wasNegative = seconds < 0 || attoseconds < 0
      var whole = seconds.magnitude
      let atto = attoseconds.magnitude
      let digits = min(max(pattern.fractionLength, 0), 18)
      var kept: UInt64 = 0
      let lead: UInt64
      var rest: [UInt64] = []
      switch pattern.fields {
      case .hourMinute:
        // Seconds round into the minute, as SwiftUI shows "0:02" for 90 seconds.
        var minutes = whole / 60
        let remainder = whole % 60
        if Self.roundsUp(nonzero: remainder > 0 || atto > 0, aboveHalf: remainder > 30 || (remainder == 30 && atto > 0),
                         atHalf: remainder == 30 && atto == 0, odd: minutes % 2 == 1, negative: wasNegative, rule: pattern.rounding) {
          minutes = Self.adding(minutes, 1)
        }
        whole = minutes * 60
        lead = minutes / 60
        rest = [minutes % 60]
      case .hourMinuteSecond, .minuteSecond:
        var scale: UInt64 = 1
        for _ in 0..<digits { scale *= 10 }
        let unit = 1_000_000_000_000_000_000 / scale
        kept = atto / unit
        let remainder = atto % unit
        let lastDigitOdd = digits == 0 ? whole % 2 == 1 : kept % 2 == 1
        if Self.roundsUp(nonzero: remainder > 0, aboveHalf: remainder * 2 > unit, atHalf: remainder * 2 == unit,
                         odd: lastDigitOdd, negative: wasNegative, rule: pattern.rounding) {
          kept += 1
          if kept == scale {
            whole = Self.adding(whole, 1)
            kept = 0
          }
        }
        if pattern.fields == .hourMinuteSecond {
          lead = whole / 3_600
          rest = [whole % 3_600 / 60, whole % 60]
        } else {
          lead = whole / 60
          rest = [whole % 60]
        }
      }
      // A duration that rounds to zero is not negative.
      let negative = wasNegative && (whole > 0 || kept > 0)
      let separator = Self.timeSeparator(locale)
      var text = negative ? "-" : ""
      let padding = min(max(pattern.padding, 1), 64)
      let leadDigits = String(lead)
      let paddedLead = String(repeating: "0", count: max(0, padding - leadDigits.count)) + leadDigits
      text += Self.field(paddedLead, integerLength: padding, grouped: lead >= 1_000, locale: locale)
      for (index, part) in rest.enumerated() {
        var digitsText = (part < 10 ? "0" : "") + String(part)
        var fraction = 0
        if index == rest.count - 1, digits > 0 {
          let fractionText = String(kept)
          digitsText += "." + String(repeating: "0", count: max(0, digits - fractionText.count)) + fractionText
          fraction = digits
        }
        text += separator + Self.field(digitsText, integerLength: 2, fractionLength: fraction, grouped: false, locale: locale)
      }
      return text
    }

    /// Whether a magnitude is rounded up by `rule`, from where its dropped part lies: past zero, past half, at half.
    /// `up` and `down` are directions of the signed value, so for a negative duration they swap.
    private static func roundsUp(nonzero: Bool, aboveHalf: Bool, atHalf: Bool, odd: Bool, negative: Bool, rule: FloatingPointRoundingRule) -> Bool {
      switch rule {
      case .towardZero: return false
      case .awayFromZero: return nonzero
      case .up: return !negative && nonzero
      case .down: return negative && nonzero
      case .toNearestOrAwayFromZero: return aboveHalf || atHalf
      case .toNearestOrEven: return aboveHalf || (atHalf && odd)
      @unknown default: return aboveHalf || (atHalf && odd)
      }
    }

    private static func adding(_ value: UInt64, _ step: UInt64) -> UInt64 {
      let (sum, overflow) = value.addingReportingOverflow(step)
      return overflow ? value : sum
    }

    /// The locale's identifier as the browser's formatters take it, or the current locale's when it has other characters.
    private static func localeTag(_ locale: Locale) -> String {
      let identifier = locale._formatterTag
      let valid = !identifier.isEmpty && identifier.utf8.allSatisfy { byte in
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x2D || byte == 0x5F
      }
      // `Locale.current` is the visitor's: the browser's formatters take an empty locale as their own.
      return valid ? identifier : ""
    }

    /// One field, given as ASCII digits already padded (`"03.456"`), written with the locale's digits and decimal
    /// separator by the browser. Without a browser (a native build) the text stays as given.
    private static func field(_ text: String, integerLength: Int, fractionLength: Int = 0, grouped: Bool, locale: Locale) -> String {
      let options = [
        "style=decimal", "scale=2", "grouping=\(grouped ? "auto" : "never")", "sign=auto", "locale=\(localeTag(locale))",
        "minInt=\(integerLength)", "minFrac=\(fractionLength)", "maxFrac=\(fractionLength)",
      ]
      return _swiftUIWebFormatNumber(text, options: options.joined(separator: ";"))
    }

    /// The locale's separator between hours and minutes (":" in English, "." in Finnish), read from how the browser
    /// writes a time of day; ":" when it cannot tell.
    private static func timeSeparator(_ locale: Locale) -> String {
      let sample = _swiftUIWebFormatDate(Date(timeIntervalSince1970: 0), options: "hour=numeric;minute=2-digit", locale: localeTag(locale))
      var separator = ""
      var seenDigit = false
      for character in sample {
        if character.isNumber {
          if !separator.isEmpty { return separator }
          seenDigit = true
        } else if seenDigit {
          separator.append(character)
        }
      }
      return ":"
    }
  }

  public func formatted<S: SwiftUIWebInternationalization.FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Duration {
    style.format(self)
  }
}

extension SwiftUIWebInternationalization.FormatStyle where Self == Duration.TimeFormatStyle {
  public static func time(pattern: Duration.TimeFormatStyle.Pattern) -> Self { Duration.TimeFormatStyle(pattern: pattern) }
}

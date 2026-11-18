// SwiftUIWeb's counterpart of Foundation's number format styles:
// `FloatingPointFormatStyle`, `IntegerFormatStyle` and their `Currency` and
// `Percent` variants, with `grouping`, `precision`, `sign` and `locale`, so
// application code such as `value.formatted(.currency(code: "BRL"))` or
// `Text(ratio, format: .percent)` compiles everywhere. The browser formats with
// `Intl.NumberFormat` (`Tools/BrowserIO/text-format.mjs`), every locale; natively
// Swift writes Foundation's output for the locales NativeNumberFormatting lists.

/// 1,234 -> "1.2K", 12,345 -> "12K", 1,500,000 -> "1.5M" (the short English names, as Foundation's
/// `.notation(.compactName)` prints in an English locale). Kept outside the gate below so the native
/// test target can reach the pure arithmetic.
func _swiftUIWebCompactNumberText(_ value: Double) -> String? {
  let magnitude = value < 0 ? -value : value
  guard magnitude >= 1000, magnitude.isFinite else { return nil }
  let suffixes = ["K", "M", "B", "T"]
  var scaled = magnitude
  var index = -1
  while scaled >= 1000 && index < suffixes.count - 1 { scaled /= 1000; index += 1 }
  let rounded = scaled < 10 ? (scaled * 10).rounded(.down) / 10 : scaled.rounded(.down)
  // Int64(rounded) traps from 2^63 on (magnitude about 9.22e30 or more); such values keep the full text.
  guard rounded < 0x1p63 else { return nil }
  let text = rounded == rounded.rounded() ? String(Int64(rounded)) : String(rounded)
  return (value < 0 ? "-" : "") + text + suffixes[index]
}

@_spi(Renderer) import SwiftUIWebCore

@_spi(Renderer) import SwiftUIWebFeatures

public enum NumberFormatStyleConfiguration {
  public struct Grouping: Hashable, Sendable {
    let never: Bool
    public static let automatic = Grouping(never: false)
    public static let never = Grouping(never: true)
  }

  public struct Precision: Hashable, Sendable {
    var minInteger: Int?
    var maxInteger: Int?
    var minFraction: Int?
    var maxFraction: Int?
    var minSignificant: Int?
    var maxSignificant: Int?

    public static func fractionLength(_ length: Int) -> NumberFormatStyleConfiguration.Precision {
      Precision(minFraction: length, maxFraction: length)
    }
    public static func fractionLength<R: RangeExpression>(_ limits: R) -> NumberFormatStyleConfiguration.Precision where R.Bound == Int {
      let (lower, upper) = bounds(limits)
      return Precision(minFraction: lower, maxFraction: upper)
    }
    public static func integerLength(_ length: Int) -> NumberFormatStyleConfiguration.Precision {
      Precision(minInteger: length, maxInteger: length)
    }
    public static func integerLength<R: RangeExpression>(_ limits: R) -> NumberFormatStyleConfiguration.Precision where R.Bound == Int {
      let (lower, upper) = bounds(limits)
      return Precision(minInteger: lower, maxInteger: upper == maxDigits ? nil : upper)
    }
    public static func integerAndFractionLength(integer: Int, fraction: Int) -> NumberFormatStyleConfiguration.Precision {
      Precision(minInteger: integer, maxInteger: integer, minFraction: fraction, maxFraction: fraction)
    }
    public static func integerAndFractionLength<R1: RangeExpression, R2: RangeExpression>(
      integerLimits: R1, fractionLimits: R2
    ) -> NumberFormatStyleConfiguration.Precision where R1.Bound == Int, R2.Bound == Int {
      let (minInteger, maxInteger) = bounds(integerLimits)
      let (minFraction, maxFraction) = bounds(fractionLimits)
      return Precision(minInteger: minInteger, maxInteger: maxInteger == maxDigits ? nil : maxInteger,
                       minFraction: minFraction, maxFraction: maxFraction)
    }
    public static func significantDigits(_ digits: Int) -> NumberFormatStyleConfiguration.Precision {
      Precision(minSignificant: digits, maxSignificant: digits)
    }
    public static func significantDigits<R: RangeExpression>(_ limits: R) -> NumberFormatStyleConfiguration.Precision where R.Bound == Int {
      let (lower, upper) = bounds(limits)
      return Precision(minSignificant: lower, maxSignificant: upper)
    }

    /// The most digits a limit names; an open upper bound (`2...`) reaches it.
    private static let maxDigits = 255

    /// The inclusive bounds of a limit, as Foundation reads it: `2...4` and `2..<5` are 2 through 4, `...4` starts at
    /// zero and `2...` has no upper bound.
    private static func bounds<R: RangeExpression>(_ limits: R) -> (Int, Int) where R.Bound == Int {
      let range = limits.relative(to: 0 ..< maxDigits + 1)
      return (range.lowerBound, Swift.max(range.lowerBound, range.upperBound - 1))
    }

    var options: [String] {
      var result: [String] = []
      if let minInteger { result.append("minInt=\(Self.clamp(minInteger))") }
      if let maxInteger { result.append("maxInt=\(Self.clamp(maxInteger))") }
      if let minFraction { result.append("minFrac=\(Self.clamp(minFraction))") }
      if let maxFraction { result.append("maxFrac=\(Self.clamp(maxFraction))") }
      if let minSignificant { result.append("minSig=\(Self.clamp(minSignificant))") }
      if let maxSignificant { result.append("maxSig=\(Self.clamp(maxSignificant))") }
      return result
    }

    private static func clamp(_ value: Int) -> Int { max(0, min(255, value)) }
  }

  public struct Notation: Hashable, Sendable {
    let compact: Bool
    public static let automatic = Notation(compact: false)
    public static let compactName = Notation(compact: true)
    public static let scientific = Notation(compact: false)
  }

  public struct SignDisplayStrategy: Hashable, Sendable {
    let option: String
    public static let automatic = SignDisplayStrategy(option: "auto")
    public static let never = SignDisplayStrategy(option: "never")
    public static func always(includingZero: Bool = true) -> SignDisplayStrategy {
      SignDisplayStrategy(option: includingZero ? "always" : "alwaysExceptZero")
    }
  }
}

/// Foundation's `CurrencyFormatStyleConfiguration`: a currency shares the number grouping and precision and has its own
/// sign strategies, among them the accounting ones (negative amounts in parentheses where the locale writes them so).
public enum CurrencyFormatStyleConfiguration {
  public typealias Grouping = NumberFormatStyleConfiguration.Grouping
  public typealias Precision = NumberFormatStyleConfiguration.Precision

  public struct SignDisplayStrategy: Hashable, Sendable {
    let number: NumberFormatStyleConfiguration.SignDisplayStrategy
    public static let automatic = SignDisplayStrategy(number: .automatic)
    public static let never = SignDisplayStrategy(number: .never)
    public static func always(showZero: Bool = true) -> SignDisplayStrategy {
      SignDisplayStrategy(number: .always(includingZero: showZero))
    }
    public static let accounting = SignDisplayStrategy(number: NumberFormatStyleConfiguration.SignDisplayStrategy(option: "accounting"))
    public static func accountingAlways(showZero: Bool = false) -> SignDisplayStrategy {
      SignDisplayStrategy(number: NumberFormatStyleConfiguration.SignDisplayStrategy(option: showZero ? "accountingAlways" : "accountingExceptZero"))
    }
  }
}

/// `code` as an ISO 4217 code (three ASCII letters, uppercased), or "" when it is not one. The code goes into the
/// option string the host parses, so nothing else may reach it.
private func _isoCurrencyCode(_ code: String) -> String {
  let bytes = code.utf8.map { $0 >= 97 && $0 <= 122 ? $0 - 32 : $0 }
  guard bytes.count == 3, bytes.allSatisfy({ $0 >= 65 && $0 <= 90 }) else { return "" }
  return String(decoding: bytes, as: UTF8.self)
}

/// `identifier` when it is a locale tag made of ASCII letters, digits, `-` and `_`, or nil.
private func _safeLocaleTag(_ identifier: String) -> String? {
  guard !identifier.isEmpty, identifier.utf8.count <= 64 else { return nil }
  let allowed = identifier.utf8.allSatisfy { byte in
    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 45 || byte == 95
  }
  return allowed ? identifier : nil
}

/// Shared option state of every number style.
struct _NumberFormatOptions: Hashable, Sendable {
  var style = "decimal"
  var currencyCode = ""
  var locale = ""
  var grouping = NumberFormatStyleConfiguration.Grouping.automatic
  var precision: NumberFormatStyleConfiguration.Precision?
  var sign = NumberFormatStyleConfiguration.SignDisplayStrategy.automatic
  /// Percent of a floating-point value scales by 100; an integer is already
  /// a percentage, as in Foundation.
  var scale = 2
  /// Integers never show a fraction unless precision asks for one.
  var integral = false
  var compact = false

  /// 1,234 -> "1.2K", 12,345 -> "12K", 1,500,000 -> "1.5M" (the short English names, as Foundation's
  /// `.notation(.compactName)` prints in an English locale).
  func compactText(_ value: Double) -> String? {
    compact ? _swiftUIWebCompactNumberText(value) : nil
  }

  func format(_ decimalText: String) -> String {
    if compact, let value = Double(decimalText), let text = compactText(value) { return text }
    var options = ["style=\(style)", "scale=\(scale)", "grouping=\(grouping.never ? "never" : "auto")", "sign=\(sign.option)"]
    let currency = _isoCurrencyCode(currencyCode)
    if !currency.isEmpty { options.append("currency=\(currency)") }
    // `Locale.current` is the visitor's, as Apple's is the user's: an empty locale is the browser formatter's own.
    options.append("locale=\(_safeLocaleTag(locale) ?? "")")
    if let precision { options += precision.options }
    else if integral { options.append("maxFrac=0") }
    return _swiftUIWebFormatNumber(decimalText, options: options.joined(separator: ";"))
  }
}

public struct FloatingPointFormatStyle<Value: BinaryFloatingPoint>: FormatStyle, Hashable, Sendable {
  var options = _NumberFormatOptions()
  public typealias Configuration = NumberFormatStyleConfiguration
  public init(locale: Locale = .current) { options.locale = locale._formatterTag }

  public func format(_ value: Value) -> String { options.format(_swiftUIWebDecimalText(value)) }
  public func locale(_ locale: Locale) -> Self { var copy = self; copy.options.locale = locale._formatterTag; return copy }
  public func grouping(_ group: FloatingPointFormatStyle<Value>.Configuration.Grouping) -> FloatingPointFormatStyle<Value> { var copy = self; copy.options.grouping = group; return copy }
  public func precision(_ p: FloatingPointFormatStyle<Value>.Configuration.Precision) -> FloatingPointFormatStyle<Value> { var copy = self; copy.options.precision = p; return copy }
  public func sign(strategy: FloatingPointFormatStyle<Value>.Configuration.SignDisplayStrategy) -> FloatingPointFormatStyle<Value> { var copy = self; copy.options.sign = strategy; return copy }
  public func notation(_ notation: FloatingPointFormatStyle<Value>.Configuration.Notation) -> FloatingPointFormatStyle<Value> { var copy = self; copy.options.compact = notation.compact; return copy }

  public struct Currency: FormatStyle, Hashable, Sendable {
    var options = _NumberFormatOptions(style: "currency")
    public typealias Configuration = CurrencyFormatStyleConfiguration
    public init(code: String, locale: Locale = .current) { options.currencyCode = code; options.locale = locale._formatterTag }
    public func format(_ value: Value) -> String { options.format(_swiftUIWebDecimalText(value)) }
    public func locale(_ locale: Locale) -> Self { var copy = self; copy.options.locale = locale._formatterTag; return copy }
    public func grouping(_ group: FloatingPointFormatStyle<Value>.Currency.Configuration.Grouping) -> FloatingPointFormatStyle<Value>.Currency { var copy = self; copy.options.grouping = group; return copy }
    public func precision(_ p: FloatingPointFormatStyle<Value>.Currency.Configuration.Precision) -> FloatingPointFormatStyle<Value>.Currency { var copy = self; copy.options.precision = p; return copy }
    public func sign(strategy: FloatingPointFormatStyle<Value>.Currency.Configuration.SignDisplayStrategy) -> FloatingPointFormatStyle<Value>.Currency { var copy = self; copy.options.sign = strategy.number; return copy }
  }

  public struct Percent: FormatStyle, Hashable, Sendable {
    var options = _NumberFormatOptions(style: "percent")
    public typealias Configuration = NumberFormatStyleConfiguration
    public init(locale: Locale = .current) { options.locale = locale._formatterTag }
    public func format(_ value: Value) -> String { options.format(_swiftUIWebDecimalText(value)) }
    public func locale(_ locale: Locale) -> Self { var copy = self; copy.options.locale = locale._formatterTag; return copy }
    public func grouping(_ group: FloatingPointFormatStyle<Value>.Percent.Configuration.Grouping) -> FloatingPointFormatStyle<Value>.Percent { var copy = self; copy.options.grouping = group; return copy }
    public func precision(_ p: FloatingPointFormatStyle<Value>.Percent.Configuration.Precision) -> FloatingPointFormatStyle<Value>.Percent { var copy = self; copy.options.precision = p; return copy }
    public func sign(strategy: FloatingPointFormatStyle<Value>.Percent.Configuration.SignDisplayStrategy) -> FloatingPointFormatStyle<Value>.Percent { var copy = self; copy.options.sign = strategy; return copy }
  }
}

public struct IntegerFormatStyle<Value: BinaryInteger>: FormatStyle, Hashable, Sendable {
  var options = _NumberFormatOptions(scale: 0, integral: true)
  public typealias Configuration = NumberFormatStyleConfiguration
  public init(locale: Locale = .current) { options.locale = locale._formatterTag }

  public func format(_ value: Value) -> String { options.format(_swiftUIWebDecimalText(value)) }
  public func _formatInteger<Other: BinaryInteger>(_ value: Other) -> String? { options.format(_swiftUIWebDecimalText(value)) }
  public func locale(_ locale: Locale) -> Self { var copy = self; copy.options.locale = locale._formatterTag; return copy }
  public func grouping(_ group: IntegerFormatStyle<Value>.Configuration.Grouping) -> IntegerFormatStyle<Value> { var copy = self; copy.options.grouping = group; return copy }
  public func precision(_ p: IntegerFormatStyle<Value>.Configuration.Precision) -> IntegerFormatStyle<Value> { var copy = self; copy.options.precision = p; return copy }
  public func sign(strategy: IntegerFormatStyle<Value>.Configuration.SignDisplayStrategy) -> IntegerFormatStyle<Value> { var copy = self; copy.options.sign = strategy; return copy }
  public func notation(_ notation: IntegerFormatStyle<Value>.Configuration.Notation) -> IntegerFormatStyle<Value> { var copy = self; copy.options.compact = notation.compact; return copy }

  public struct Currency: FormatStyle, Hashable, Sendable {
    var options = _NumberFormatOptions(style: "currency", scale: 0)
    public typealias Configuration = CurrencyFormatStyleConfiguration
    public init(code: String, locale: Locale = .current) { options.currencyCode = code; options.locale = locale._formatterTag }
    public func format(_ value: Value) -> String { options.format(_swiftUIWebDecimalText(value)) }
    public func _formatInteger<Other: BinaryInteger>(_ value: Other) -> String? { options.format(_swiftUIWebDecimalText(value)) }
    public func locale(_ locale: Locale) -> Self { var copy = self; copy.options.locale = locale._formatterTag; return copy }
    public func grouping(_ group: IntegerFormatStyle<Value>.Currency.Configuration.Grouping) -> IntegerFormatStyle<Value>.Currency { var copy = self; copy.options.grouping = group; return copy }
    public func precision(_ p: IntegerFormatStyle<Value>.Currency.Configuration.Precision) -> IntegerFormatStyle<Value>.Currency { var copy = self; copy.options.precision = p; return copy }
    public func sign(strategy: IntegerFormatStyle<Value>.Currency.Configuration.SignDisplayStrategy) -> IntegerFormatStyle<Value>.Currency { var copy = self; copy.options.sign = strategy.number; return copy }
  }

  public struct Percent: FormatStyle, Hashable, Sendable {
    var options = _NumberFormatOptions(style: "percent", scale: 0, integral: true)
    public typealias Configuration = NumberFormatStyleConfiguration
    public init(locale: Locale = .current) { options.locale = locale._formatterTag }
    public func format(_ value: Value) -> String { options.format(_swiftUIWebDecimalText(value)) }
    public func _formatInteger<Other: BinaryInteger>(_ value: Other) -> String? { options.format(_swiftUIWebDecimalText(value)) }
    public func locale(_ locale: Locale) -> Self { var copy = self; copy.options.locale = locale._formatterTag; return copy }
    public func grouping(_ group: IntegerFormatStyle<Value>.Percent.Configuration.Grouping) -> IntegerFormatStyle<Value>.Percent { var copy = self; copy.options.grouping = group; return copy }
    public func precision(_ p: IntegerFormatStyle<Value>.Percent.Configuration.Precision) -> IntegerFormatStyle<Value>.Percent { var copy = self; copy.options.precision = p; return copy }
    public func sign(strategy: IntegerFormatStyle<Value>.Percent.Configuration.SignDisplayStrategy) -> IntegerFormatStyle<Value>.Percent { var copy = self; copy.options.sign = strategy; return copy }
  }
}

public extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
  static var number: FloatingPointFormatStyle<Double> { FloatingPointFormatStyle<Double>() }
}
public extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Percent {
  static var percent: FloatingPointFormatStyle<Double>.Percent { FloatingPointFormatStyle<Double>.Percent() }
}
public extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Currency {
  static func currency(code: String) -> FloatingPointFormatStyle<Double>.Currency { FloatingPointFormatStyle<Double>.Currency(code: code) }
}
public extension FormatStyle where Self == FloatingPointFormatStyle<Float> {
  static var number: FloatingPointFormatStyle<Float> { FloatingPointFormatStyle<Float>() }
}
public extension FormatStyle where Self == FloatingPointFormatStyle<Float>.Percent {
  static var percent: FloatingPointFormatStyle<Float>.Percent { FloatingPointFormatStyle<Float>.Percent() }
}
public extension FormatStyle where Self == FloatingPointFormatStyle<Float>.Currency {
  static func currency(code: String) -> FloatingPointFormatStyle<Float>.Currency { FloatingPointFormatStyle<Float>.Currency(code: code) }
}
public extension FormatStyle where Self == IntegerFormatStyle<Int> {
  static var number: IntegerFormatStyle<Int> { IntegerFormatStyle<Int>() }
}
public extension FormatStyle where Self == IntegerFormatStyle<Int>.Percent {
  static var percent: IntegerFormatStyle<Int>.Percent { IntegerFormatStyle<Int>.Percent() }
}
public extension FormatStyle where Self == IntegerFormatStyle<Int>.Currency {
  static func currency(code: String) -> IntegerFormatStyle<Int>.Currency { IntegerFormatStyle<Int>.Currency(code: code) }
}

public extension BinaryFloatingPoint {
  func formatted<F: SwiftUIWebInternationalization.FormatStyle>(_ format: F) -> F.FormatOutput where F.FormatInput == Self {
    format.format(self)
  }
  func formatted() -> String { FloatingPointFormatStyle<Self>().format(self) }
}

public extension BinaryInteger {
  func formatted<F: SwiftUIWebInternationalization.FormatStyle>(_ format: F) -> F.FormatOutput where F.FormatInput == Self {
    format.format(self)
  }
  /// Foundation's overload for a style of another integer type: `Int64(5).formatted(.number)` formats with an
  /// `IntegerFormatStyle<Int>`. A value that type cannot hold is formatted whole rather than trapping.
  func formatted<F: SwiftUIWebInternationalization.FormatStyle>(_ format: F) -> F.FormatOutput where F.FormatInput: BinaryInteger {
    if let exact = F.FormatInput(exactly: self) { return format.format(exact) }
    if let whole = format._formatInteger(self) { return whole }
    return format.format(F.FormatInput(clamping: self))
  }
  func formatted() -> String { IntegerFormatStyle<Self>().format(self) }
}
public extension LocalizedStringKey.StringInterpolation {
  /// `Text("\(count, format: .number.notation(.compactName))")`: the value formatted now, as a string argument.
  mutating func appendInterpolation<F: SwiftUIWebInternationalization.FormatStyle>(_ value: F.FormatInput, format: F) where F.FormatOutput == String {
    _appendString(format.format(value))
  }
}

// Foundation's unit formatting for browser and Embedded builds: `UnitMass`, `UnitLength`, `Formatter.UnitStyle`,
// `MeasurementFormatter` and `Measurement.FormatStyle`. `MeasurementFormatter` follows Foundation's defaults: a
// measurement converts to the locale's preferred unit (`MeasurementPreferences.swift`) unless `.providedUnit` is set,
// and the unit name and number come from the browser's `Intl.NumberFormat` in the locale. Without a browser host, and
// for units `Intl` does not name, the English names are used.
//
// Not reproduced: `naturalScale` (a magnitude-based unit choice) and `Measurement.FormatStyle`, which still shows units
// as provided with English names.
import SwiftUIWebBrowserIO
import SwiftUIWebInternationalization

/// A unit of mass. Conversions between mass units go through kilograms.
public final class UnitMass: Unit, @unchecked Sendable {
  let kilogramsPerUnit: Double
  let abbreviation: String
  let narrowSymbol: String
  let wideName: String
  /// The CLDR unit name, as the locale preferences and `Intl.NumberFormat` know it.
  let identifier: String

  private init(symbol: String, kilogramsPerUnit: Double, abbreviation: String, narrowSymbol: String, wideName: String, identifier: String) {
    self.kilogramsPerUnit = kilogramsPerUnit
    self.abbreviation = abbreviation
    self.narrowSymbol = narrowSymbol
    self.wideName = wideName
    self.identifier = identifier
    super.init(symbol: symbol)
  }

  override package func _baseValue(_ value: Double) -> Double { value * kilogramsPerUnit }
  override package func _value(fromBase value: Double) -> Double { value / kilogramsPerUnit }

  public static let kilograms = UnitMass(symbol: "kg", kilogramsPerUnit: 1, abbreviation: "kg", narrowSymbol: "kg", wideName: "kilograms", identifier: "kilogram")
  public static let grams = UnitMass(symbol: "g", kilogramsPerUnit: 0.001, abbreviation: "g", narrowSymbol: "g", wideName: "grams", identifier: "gram")
  public static let milligrams = UnitMass(symbol: "mg", kilogramsPerUnit: 0.000_001, abbreviation: "mg", narrowSymbol: "mg", wideName: "milligrams", identifier: "milligram")
  public static let micrograms = UnitMass(symbol: "µg", kilogramsPerUnit: 0.000_000_001, abbreviation: "µg", narrowSymbol: "µg", wideName: "micrograms", identifier: "microgram")
  public static let nanograms = UnitMass(symbol: "ng", kilogramsPerUnit: 0.000_000_000_001, abbreviation: "ng", narrowSymbol: "ng", wideName: "nanograms", identifier: "nanogram")
  public static let ounces = UnitMass(symbol: "oz", kilogramsPerUnit: 0.028_349_523_125, abbreviation: "oz", narrowSymbol: "oz", wideName: "ounces", identifier: "ounce")
  public static let ouncesTroy = UnitMass(symbol: "oz t", kilogramsPerUnit: 0.031_103_476_8, abbreviation: "oz t", narrowSymbol: "oz t", wideName: "troy ounces", identifier: "ounce-troy")
  public static let pounds = UnitMass(symbol: "lb", kilogramsPerUnit: 0.453_592_37, abbreviation: "lb", narrowSymbol: "lb", wideName: "pounds", identifier: "pound")
  public static let stones = UnitMass(symbol: "st", kilogramsPerUnit: 6.350_293_18, abbreviation: "st", narrowSymbol: "st", wideName: "stones", identifier: "stone")
  public static let metricTons = UnitMass(symbol: "t", kilogramsPerUnit: 1_000, abbreviation: "t", narrowSymbol: "t", wideName: "metric tons", identifier: "metric-ton")
  public static let shortTons = UnitMass(symbol: "ton", kilogramsPerUnit: 907.184_74, abbreviation: "tn", narrowSymbol: "tn", wideName: "tons", identifier: "ton")
  public static let carats = UnitMass(symbol: "ct", kilogramsPerUnit: 0.000_2, abbreviation: "ct", narrowSymbol: "ct", wideName: "carats", identifier: "carat")
  public static let slugs = UnitMass(symbol: "slug", kilogramsPerUnit: 14.593_902_94, abbreviation: "slug", narrowSymbol: "slug", wideName: "slugs", identifier: "slug")

  /// The unit with a CLDR identifier from the preference tables. Unknown identifiers name kilograms.
  static func named(_ identifier: String) -> UnitMass {
    switch identifier {
    case "gram": UnitMass.grams
    case "pound": UnitMass.pounds
    case "ounce": UnitMass.ounces
    case "stone": UnitMass.stones
    case "metric-ton": UnitMass.metricTons
    default: UnitMass.kilograms
    }
  }
}


/// A unit of length. Conversions between length units go through meters.
public final class UnitLength: Unit, @unchecked Sendable {
  let metersPerUnit: Double
  let abbreviation: String
  let wideName: String
  /// The CLDR unit name, as the locale preferences and `Intl.NumberFormat` know it.
  let identifier: String

  private init(symbol: String, metersPerUnit: Double, abbreviation: String, wideName: String, identifier: String) {
    self.metersPerUnit = metersPerUnit
    self.abbreviation = abbreviation
    self.wideName = wideName
    self.identifier = identifier
    super.init(symbol: symbol)
  }

  override package func _baseValue(_ value: Double) -> Double { value * metersPerUnit }
  override package func _value(fromBase value: Double) -> Double { value / metersPerUnit }

  public static let meters = UnitLength(symbol: "m", metersPerUnit: 1, abbreviation: "m", wideName: "meters", identifier: "meter")
  public static let kilometers = UnitLength(symbol: "km", metersPerUnit: 1_000, abbreviation: "km", wideName: "kilometers", identifier: "kilometer")
  public static let centimeters = UnitLength(symbol: "cm", metersPerUnit: 0.01, abbreviation: "cm", wideName: "centimeters", identifier: "centimeter")
  public static let millimeters = UnitLength(symbol: "mm", metersPerUnit: 0.001, abbreviation: "mm", wideName: "millimeters", identifier: "millimeter")
  public static let feet = UnitLength(symbol: "ft", metersPerUnit: 0.3048, abbreviation: "ft", wideName: "feet", identifier: "foot")
  public static let inches = UnitLength(symbol: "in", metersPerUnit: 0.0254, abbreviation: "in", wideName: "inches", identifier: "inch")
  public static let yards = UnitLength(symbol: "yd", metersPerUnit: 0.9144, abbreviation: "yd", wideName: "yards", identifier: "yard")
  public static let miles = UnitLength(symbol: "mi", metersPerUnit: 1_609.344, abbreviation: "mi", wideName: "miles", identifier: "mile")

  /// The unit with a CLDR identifier from the preference tables. Unknown identifiers name meters.
  static func named(_ identifier: String) -> UnitLength {
    switch identifier {
    case "kilometer": UnitLength.kilometers
    case "mile": UnitLength.miles
    case "foot": UnitLength.feet
    default: UnitLength.meters
    }
  }
}


/// Foundation's base class for formatters of Foundation values.
open class Formatter: NSObject {
  /// How a unit is spelled: `.short` is the narrow symbol (`70kg`), `.medium` the abbreviation (`70 kg`), `.long` the
  /// name (`70 kilograms`).
  public enum UnitStyle: Int, Sendable {
    case short = 1
    case medium = 2
    case long = 3
  }
}

/// Formats a `Measurement` as a number and its unit, as Foundation's `MeasurementFormatter` does. Final: Embedded
/// Swift does not allow the generic `string(from:)` in an open class.
public final class MeasurementFormatter: Formatter {
  public struct UnitOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// Shows the unit the measurement was given in instead of the locale's preferred unit.
    public static let providedUnit = UnitOptions(rawValue: 1 << 0)
    /// Accepted for source compatibility: units are never chosen by magnitude.
    public static let naturalScale = UnitOptions(rawValue: 1 << 1)
    /// Accepted for source compatibility: temperatures always show their unit.
    public static let temperatureWithoutUnit = UnitOptions(rawValue: 1 << 2)
  }

  public var unitOptions: UnitOptions = []
  public var unitStyle: Formatter.UnitStyle = .medium
  /// Its `maximumFractionDigits` bounds the digits of the value.
  public var numberFormatter = NumberFormatter()
  public var locale: Locale! = .current

  public func string<UnitType: Unit>(from measurement: Measurement<UnitType>) -> String {
    let (value, unit) = displayed(measurement.value, measurement.unit)
    let digits = max(0, numberFormatter.maximumFractionDigits)
    let current = locale ?? .current
    let name = identifier(of: unit)
    if _MeasurementPreferences.hasIntlName(name),
       let text = BrowserIntl.formatUnit(
         value: value,
         identifier: name,
         display: intlDisplay,
         locale: current.identifier,
         maximumFractionDigits: digits
       ) {
      return text
    }
    let number = FloatingPointFormatStyle<Double>(locale: current)
      .precision(.fractionLength(0 ... digits))
      .format(value)
    switch unitStyle {
    case .short: return number + englishNarrow(unit)
    case .medium: return number + " " + englishAbbreviation(unit)
    case .long: return number + " " + englishWideName(unit)
    }
  }

  /// The `Intl` display for the unit style: `.short` is `narrow`, `.medium` is `short` and `.long` is `long`.
  private var intlDisplay: String {
    switch unitStyle {
    case .short: "narrow"
    case .medium: "short"
    case .long: "long"
    }
  }

  /// The value and unit a measurement is shown in: its own unit with `.providedUnit`, otherwise the locale's preferred
  /// unit when the locale does not already list the given one.
  private func displayed(_ value: Double, _ unit: Unit) -> (Double, Unit) {
    if unitOptions.contains(.providedUnit) { return (value, unit) }
    let current = locale ?? .current
    let region = _MeasurementPreferences.effectiveRegion(current.regionCode, language: current.languageCode)
    if let mass = unit as? UnitMass {
      let identifiers = _MeasurementPreferences.massIdentifiers(region: region)
      if identifiers.contains(mass.identifier) { return (value, unit) }
      let target = UnitMass.named(identifiers[0])
      return (value * mass.kilogramsPerUnit / target.kilogramsPerUnit, target)
    }
    if let length = unit as? UnitLength {
      let identifiers = _MeasurementPreferences.lengthIdentifiers(region: region)
      if identifiers.contains(length.identifier) { return (value, unit) }
      let target = UnitLength.named(identifiers[0])
      return (value * length.metersPerUnit / target.metersPerUnit, target)
    }
    if let temperature = unit as? UnitTemperature {
      let identifiers = _MeasurementPreferences.temperatureIdentifiers(region: region)
      if identifiers.contains(temperature.identifier) { return (value, unit) }
      let target = UnitTemperature.named(identifiers[0])
      return (target.fromKelvin(temperature.toKelvin(value)), target)
    }
    return (value, unit)
  }

  private func identifier(of unit: Unit) -> String {
    if let mass = unit as? UnitMass { return mass.identifier }
    if let length = unit as? UnitLength { return length.identifier }
    if let temperature = unit as? UnitTemperature { return temperature.identifier }
    return unit.symbol
  }

  private func englishNarrow(_ unit: Unit) -> String {
    if let mass = unit as? UnitMass { return mass.narrowSymbol }
    return unit.symbol
  }

  private func englishAbbreviation(_ unit: Unit) -> String {
    if let mass = unit as? UnitMass { return mass.abbreviation }
    if let length = unit as? UnitLength { return length.abbreviation }
    return unit.symbol
  }

  private func englishWideName(_ unit: Unit) -> String {
    if let mass = unit as? UnitMass { return mass.wideName }
    if let length = unit as? UnitLength { return length.wideName }
    if let temperature = unit as? UnitTemperature { return temperature.wideName }
    return unit.symbol
  }
}

extension Measurement {
  public struct FormatStyle: SwiftUIWebInternationalization.FormatStyle, Hashable, Sendable {
    /// How a unit's name is spelled by `Measurement.FormatStyle`.
    public struct UnitWidth: Hashable, Sendable {
      private let raw: Int
      private init(raw: Int) { self.raw = raw }

      // Computed: Embedded Swift has no static stored properties in generic types.
      public static var abbreviated: UnitWidth { UnitWidth(raw: 0) }
      public static var narrow: UnitWidth { UnitWidth(raw: 1) }
      public static var wide: UnitWidth { UnitWidth(raw: 3) }
    }

    public typealias FormatInput = Measurement<UnitType>
    public typealias FormatOutput = String

    public var width: UnitWidth
    public var locale: Locale
    public var numberFormatStyle: FloatingPointFormatStyle<Double>?

    public init(width: Measurement<UnitType>.FormatStyle.UnitWidth, locale: Locale = .current, numberFormatStyle: FloatingPointFormatStyle<Double>? = nil) {
      self.width = width
      self.locale = locale
      self.numberFormatStyle = numberFormatStyle
    }

    public init() {
      self.init(width: .abbreviated)
    }

    public func locale(_ locale: Locale) -> Measurement<UnitType>.FormatStyle {
      var copy = self
      copy.locale = locale
      return copy
    }

    public func format(_ measurement: Measurement<UnitType>) -> String {
      let style = numberFormatStyle ?? FloatingPointFormatStyle<Double>(locale: locale)
      let number = style.locale(locale).format(measurement.value)
      let separator = width == .narrow ? "" : " "
      return number + separator + _unitName(measurement.unit)
    }

    private func _unitName(_ unit: UnitType) -> String {
      guard let mass = unit as? UnitMass else { return unit.symbol }
      switch width {
      case .narrow: return mass.narrowSymbol
      case .wide: return mass.wideName
      default: return mass.abbreviation
      }
    }
  }

  /// Foundation's `Measurement.formatted(_:)`: the measurement as the format style spells it.
  public func formatted<S: SwiftUIWebInternationalization.FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Measurement<UnitType> {
    style.format(self)
  }
}

extension SwiftUIWebInternationalization.FormatStyle {
  /// Foundation's `FormatStyle.measurement(width:usage:numberFormatStyle:)`, without `usage`.
  public static func measurement<UnitType: Unit>(
    width: Measurement<UnitType>.FormatStyle.UnitWidth,
    numberFormatStyle: FloatingPointFormatStyle<Double>? = nil
  ) -> Self where Self == Measurement<UnitType>.FormatStyle {
    Measurement<UnitType>.FormatStyle(width: width, numberFormatStyle: numberFormatStyle)
  }
}

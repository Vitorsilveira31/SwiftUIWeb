@_spi(Renderer) import SwiftUIWebCore
#if canImport(SwiftUIWebInternationalization)
import SwiftUIWebInternationalization
#endif

// Swift Charts' axis API: `AxisMarks` with a per-value content builder
// (`AxisGridLine`, `AxisTick`, `AxisValueLabel`), tick-value generators
// (`AxisMarkValues`, `DateBins`), `AxisValue`, and `AutomaticScaleDomain`.
// Everything is value-typed and closure-based so it builds for Embedded Swift.

/// One axis value handed to the content closure of `AxisMarks`.
public struct AxisValue {
  public let index: Int
  public let count: Int
  let chartValue: ChartValue

  /// The value converted to a plottable type, or `nil` when it has another
  /// type (a category is not a `Double`).
  public func `as`<T: Plottable>(_ type: T.Type) -> T? { T._fromChartValue(chartValue) }
}

public struct AxisMarkPreset: Hashable, Sendable {
  let name: String
  public static let automatic = AxisMarkPreset(name: "automatic")
  public static let aligned = AxisMarkPreset(name: "aligned")
  public static let extended = AxisMarkPreset(name: "extended")
  public static let inset = AxisMarkPreset(name: "inset")
}

public struct AxisMarkPosition: Hashable, Sendable {
  let name: String
  public static let automatic = AxisMarkPosition(name: "automatic")
  public static let leading = AxisMarkPosition(name: "leading")
  public static let trailing = AxisMarkPosition(name: "trailing")
  public static let top = AxisMarkPosition(name: "top")
  public static let bottom = AxisMarkPosition(name: "bottom")
}

/// Where an axis puts its marks.
public struct AxisMarkValues: Hashable, Sendable {
  enum Kind: Hashable, Sendable { case automatic, stride }
  let kind: Kind
  var desiredCount: Int?
  var minimumStride: Double?
  /// Seconds or units between marks for `.stride`.
  var step: Double = 0
  var roundLowerBound: Bool?
  var roundUpperBound: Bool?

  public static var automatic: AxisMarkValues { AxisMarkValues(kind: .automatic) }
  public static func automatic(desiredCount: Int? = nil, roundLowerBound: Bool? = nil, roundUpperBound: Bool? = nil) -> AxisMarkValues {
    AxisMarkValues(kind: .automatic, desiredCount: desiredCount, roundLowerBound: roundLowerBound, roundUpperBound: roundUpperBound)
  }
  public static func automatic(minimumStride: Double, desiredCount: Int? = nil, roundLowerBound: Bool? = nil, roundUpperBound: Bool? = nil) -> AxisMarkValues {
    AxisMarkValues(kind: .automatic, desiredCount: desiredCount, minimumStride: minimumStride, roundLowerBound: roundLowerBound, roundUpperBound: roundUpperBound)
  }
  public static func stride(by step: Double, roundLowerBound: Bool? = nil, roundUpperBound: Bool? = nil) -> AxisMarkValues {
    AxisMarkValues(kind: .stride, step: step, roundLowerBound: roundLowerBound, roundUpperBound: roundUpperBound)
  }
  /// A mark every `count` calendar units. Months and years use their mean
  /// length, since marks are placed on a continuous scale.
  public static func stride(by component: Calendar.Component, count: Int = 1, roundLowerBound: Bool? = nil, roundUpperBound: Bool? = nil) -> AxisMarkValues {
    AxisMarkValues(kind: .stride, step: _chartSeconds(component) * Double(max(count, 1)), roundLowerBound: roundLowerBound, roundUpperBound: roundUpperBound)
  }
}

func _chartSeconds(_ component: Calendar.Component) -> Double {
  switch component {
  case .nanosecond: return 0.000000001
  case .second: return 1
  case .minute: return 60
  case .hour: return 3_600
  case .day, .weekday, .weekdayOrdinal: return 86_400
  case .weekOfMonth, .weekOfYear, .yearForWeekOfYear: return 604_800
  case .month: return 2_629_800
  case .quarter: return 7_889_400
  case .year, .era: return 31_557_600
  default: return 1
  }
}

/// Evenly spaced dates, for `AxisMarks(values: DateBins(...).thresholds)`.
public struct DateBins {
  public let thresholds: [Date]

  public init(unit: Calendar.Component, by count: Int = 1, calendar: Calendar = .current, range: ClosedRange<Date>) {
    var dates: [Date] = [range.lowerBound]
    var current = range.lowerBound
    let stride = max(count, 1)
    while dates.count < 10_000, let next = calendar.date(byAdding: unit, value: stride, to: current), next > current, next <= range.upperBound {
      dates.append(next)
      current = next
    }
    thresholds = dates
  }
}

public struct AutomaticScaleDomain: Hashable, Sendable {
  var includesZero: Bool?
  var reversed: Bool
  public static var automatic: AutomaticScaleDomain { AutomaticScaleDomain(includesZero: nil, reversed: false) }
  public static func automatic(includesZero: Bool? = nil, reversed: Bool = false) -> AutomaticScaleDomain {
    AutomaticScaleDomain(includesZero: includesZero, reversed: reversed)
  }
}

// MARK: Marks

/// A mark drawn for one axis value: tick, grid line or label.
public struct _AxisItem {
  enum Kind { case gridLine, tick, label }
  var kind: Kind
  var stroke: StrokeStyle? = nil
  var centered: Bool? = nil
  var tickLength: Double? = nil
  var text: String? = nil
  var format: ((Double) -> String)? = nil
  var view: AnyView? = nil
}

public protocol AxisMark {
  func _axisItems() -> [_AxisItem]
}

public protocol AxisContent {
  func _axisMarksList() -> [AxisMarks]
}

public struct _AxisMarkGroup: AxisMark {
  let items: [_AxisItem]
  public func _axisItems() -> [_AxisItem] { items }
}

@resultBuilder public enum AxisMarkBuilder {
  public static func buildBlock() -> _AxisMarkGroup { _AxisMarkGroup(items: []) }
  public static func buildBlock<M: AxisMark>(_ m: M) -> _AxisMarkGroup { _AxisMarkGroup(items: m._axisItems()) }
  public static func buildBlock<M0: AxisMark, M1: AxisMark>(_ m0: M0, _ m1: M1) -> _AxisMarkGroup { _AxisMarkGroup(items: m0._axisItems() + m1._axisItems()) }
  public static func buildBlock<M0: AxisMark, M1: AxisMark, M2: AxisMark>(_ m0: M0, _ m1: M1, _ m2: M2) -> _AxisMarkGroup { _AxisMarkGroup(items: m0._axisItems() + m1._axisItems() + m2._axisItems()) }
  public static func buildBlock<M0: AxisMark, M1: AxisMark, M2: AxisMark, M3: AxisMark>(_ m0: M0, _ m1: M1, _ m2: M2, _ m3: M3) -> _AxisMarkGroup { _AxisMarkGroup(items: m0._axisItems() + m1._axisItems() + m2._axisItems() + m3._axisItems()) }
  public static func buildBlock<M0: AxisMark, M1: AxisMark, M2: AxisMark, M3: AxisMark, M4: AxisMark>(_ m0: M0, _ m1: M1, _ m2: M2, _ m3: M3, _ m4: M4) -> _AxisMarkGroup { _AxisMarkGroup(items: m0._axisItems() + m1._axisItems() + m2._axisItems() + m3._axisItems() + m4._axisItems()) }
  public static func buildOptional(_ component: _AxisMarkGroup?) -> _AxisMarkGroup { component ?? _AxisMarkGroup(items: []) }
  public static func buildEither(first: _AxisMarkGroup) -> _AxisMarkGroup { first }
  public static func buildEither(second: _AxisMarkGroup) -> _AxisMarkGroup { second }
}

public struct _AxisContentGroup: AxisContent {
  let marks: [AxisMarks]
  public func _axisMarksList() -> [AxisMarks] { marks }
}

@resultBuilder public enum AxisContentBuilder {
  public static func buildBlock() -> _AxisContentGroup { _AxisContentGroup(marks: []) }
  public static func buildBlock<C: AxisContent>(_ c: C) -> _AxisContentGroup { _AxisContentGroup(marks: c._axisMarksList()) }
  public static func buildBlock<C0: AxisContent, C1: AxisContent>(_ c0: C0, _ c1: C1) -> _AxisContentGroup { _AxisContentGroup(marks: c0._axisMarksList() + c1._axisMarksList()) }
  public static func buildBlock<C0: AxisContent, C1: AxisContent, C2: AxisContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> _AxisContentGroup { _AxisContentGroup(marks: c0._axisMarksList() + c1._axisMarksList() + c2._axisMarksList()) }
  public static func buildOptional(_ component: _AxisContentGroup?) -> _AxisContentGroup { component ?? _AxisContentGroup(marks: []) }
  public static func buildEither(first: _AxisContentGroup) -> _AxisContentGroup { first }
  public static func buildEither(second: _AxisContentGroup) -> _AxisContentGroup { second }
}

public struct AxisGridLine: AxisMark {
  let centered: Bool?
  let stroke: StrokeStyle?
  public init(centered: Bool? = nil, stroke: StrokeStyle? = nil) { self.centered = centered; self.stroke = stroke }
  public func _axisItems() -> [_AxisItem] { [_AxisItem(kind: .gridLine, stroke: stroke, centered: centered)] }
}

public struct AxisTick: AxisMark {
  public struct Length: Hashable, Sendable {
    let points: Double?
    public static let automatic = Length(points: nil)
    public static let label = Length(points: nil)
    public static let longestLabel = Length(points: nil)
    public static func value(_ points: Double) -> Length { Length(points: points) }
  }
  let centered: Bool?
  let length: Length
  let stroke: StrokeStyle?
  public init(centered: Bool? = nil, length: Length = .automatic, stroke: StrokeStyle? = nil) {
    self.centered = centered; self.length = length; self.stroke = stroke
  }
  public func _axisItems() -> [_AxisItem] { [_AxisItem(kind: .tick, stroke: stroke, centered: centered, tickLength: length.points)] }
}

public struct AxisValueLabel: AxisMark {
  private var item: _AxisItem

  /// The value's default text: numbers as written, dates as month and day.
  public init(centered: Bool? = nil) { item = _AxisItem(kind: .label, centered: centered) }
  public init(_ text: String, centered: Bool? = nil) { item = _AxisItem(kind: .label, centered: centered, text: text) }
  /// A label built from a view, drawn in an SVG `foreignObject`.
  @MainActor public init<V: View>(centered: Bool? = nil, @ViewBuilder content: () -> V) {
    item = _AxisItem(kind: .label, centered: centered, view: AnyView(content()))
  }
  public func _axisItems() -> [_AxisItem] { [item] }
}

#if canImport(SwiftUIWebInternationalization)
extension AxisValueLabel {
  public init<F: FormatStyle>(format: F, centered: Bool? = nil) where F.FormatInput == Int, F.FormatOutput == String {
    // A tick Int cannot hold (past 2^31 in the browser build) is written as a whole number rather than trapping.
    self.init(centered: centered, formatter: { value in
      // Past Int, a style that formats any integer (IntegerFormatStyle) still formats it, grouped as the others are.
      Int(exactly: value.rounded()).map { format.format($0) }
        ?? Int64(exactly: value.rounded()).flatMap { format._formatInteger($0) ?? String($0) } ?? String(value)
    })
  }
  public init<F: FormatStyle>(format: F, centered: Bool? = nil) where F.FormatInput == Double, F.FormatOutput == String {
    self.init(centered: centered, formatter: { format.format($0) })
  }
  public init<F: FormatStyle>(format: F, centered: Bool? = nil) where F.FormatInput == Date, F.FormatOutput == String {
    self.init(centered: centered, formatter: { format.format(Date(timeIntervalSince1970: $0)) })
  }
  private init(centered: Bool?, formatter: @escaping (Double) -> String) {
    item = _AxisItem(kind: .label, centered: centered, format: formatter)
  }
}
#endif

public struct AxisMarks: AxisContent {
  public enum Visibility: Hashable, Sendable { case automatic, visible, hidden }
  public let visibility: Visibility
  /// Explicit positions of the original, content-less form.
  public let values: [Double]?
  let valueSpec: AxisMarkValues
  let explicitValues: [ChartValue]?
  let stroke: StrokeStyle?
  let content: (@MainActor (AxisValue) -> [_AxisItem])?
  /// True for marks built with the Swift Charts initializers: they replace
  /// the default axis instead of only toggling its visibility.
  let isCustom: Bool
  /// The side the marks sit on. Swift Charts puts y marks on the trailing side unless they ask for `.leading`.
  let position: AxisMarkPosition

  public init(_ visibility: Visibility, values: [Double]? = nil) {
    isCustom = false
    position = .automatic
    self.visibility = visibility
    self.values = values
    valueSpec = .automatic
    explicitValues = nil
    stroke = nil
    content = nil
  }
  public static var automatic: AxisMarks { AxisMarks(.automatic) }
  public static var visible: AxisMarks { AxisMarks(.visible) }
  public static var hidden: AxisMarks { AxisMarks(.hidden) }

  private init(position: AxisMarkPosition, valueSpec: AxisMarkValues, explicitValues: [ChartValue]?, stroke: StrokeStyle?, content: (@MainActor (AxisValue) -> [_AxisItem])?) {
    isCustom = true
    self.position = position
    visibility = .visible
    values = nil
    self.valueSpec = valueSpec
    self.explicitValues = explicitValues
    self.stroke = stroke
    self.content = content
  }

  /// Marks for the axis's automatically chosen values. `preset` is accepted for source compatibility and has no
  /// effect; x marks sit below the plot, and y marks on its trailing side, as in Swift Charts, or on its leading side
  /// for `position: .leading`.
  public init<Marks: AxisMark>(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: AxisMarkValues = .automatic, stroke: StrokeStyle? = nil, @AxisMarkBuilder content: @escaping @MainActor (AxisValue) -> Marks) {
    self.init(position: position, valueSpec: values, explicitValues: nil, stroke: stroke, content: { content($0)._axisItems() })
  }
  public init(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: AxisMarkValues = .automatic, stroke: StrokeStyle? = nil) {
    self.init(position: position, valueSpec: values, explicitValues: nil, stroke: stroke, content: nil)
  }
  public init<V: Plottable, Marks: AxisMark>(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: [V], stroke: StrokeStyle? = nil, @AxisMarkBuilder content: @escaping @MainActor (AxisValue) -> Marks) {
    self.init(position: position, valueSpec: .automatic, explicitValues: values.map { $0._chartValue(label: "") }, stroke: stroke, content: { content($0)._axisItems() })
  }
  public init<V: Plottable>(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: [V], stroke: StrokeStyle? = nil) {
    self.init(position: position, valueSpec: .automatic, explicitValues: values.map { $0._chartValue(label: "") }, stroke: stroke, content: nil)
  }

  public func _axisMarksList() -> [AxisMarks] { [self] }

  @MainActor func items(for value: AxisValue) -> [_AxisItem] {
    if let content { return content(value) }
    return [
      _AxisItem(kind: .gridLine, stroke: stroke),
      _AxisItem(kind: .tick),
      _AxisItem(kind: .label)
    ]
  }
}

// MARK: Tick values

/// Places an axis's marks inside `lower...upper`.
func _chartAxisValues(_ spec: AxisMarkValues, lower: Double, upper: Double, isDate: Bool) -> [Double] {
  guard upper > lower else { return [lower] }
  let range = upper - lower
  let step: Double
  switch spec.kind {
  case .stride:
    step = max(spec.step, range / 500)
  case .automatic:
    // Swift Charts marks a date axis by calendar units, about three of them across a plot (a week apart over two
    // weeks), and a number axis about five times.
    let desired = Double(max(spec.desiredCount ?? (isDate ? 3 : 5), 2))
    var automaticStep = isDate ? _chartTimeStep(range: range, desired: desired) : _chartNiceStep(range / desired)
    if let minimum = spec.minimumStride {
      while automaticStep < minimum { automaticStep = _chartNextNiceStep(automaticStep) }
    }
    step = automaticStep
  }
  var values: [Double] = []
  var tick = (lower / step).rounded(.up) * step
  var guardCount = 0
  while tick <= upper + step * 0.000001 && guardCount < 500 {
    values.append(tick)
    tick += step
    guardCount += 1
  }
  return values
}

private func _chartMagnitude(_ value: Double) -> Double {
  var magnitude = 1.0
  var guardCount = 0
  while value >= magnitude * 10 && guardCount < 300 { magnitude *= 10; guardCount += 1 }
  while value < magnitude && guardCount < 600 { magnitude /= 10; guardCount += 1 }
  return magnitude
}

func _chartNiceStep(_ raw: Double) -> Double {
  guard raw > 0, raw.isFinite else { return 1 }
  let magnitude = _chartMagnitude(raw)
  let normalized = raw / magnitude
  if normalized <= 1 { return magnitude }
  if normalized <= 2 { return 2 * magnitude }
  if normalized <= 5 { return 5 * magnitude }
  return 10 * magnitude
}

private func _chartNextNiceStep(_ step: Double) -> Double {
  let magnitude = _chartMagnitude(step)
  let normalized = step / magnitude
  if normalized < 1.5 { return 2 * magnitude }
  if normalized < 3 { return 5 * magnitude }
  return 10 * magnitude
}

private let _chartTimeSteps: [Double] = [
  1, 5, 15, 30, 60, 300, 900, 1_800, 3_600, 10_800, 21_600, 43_200,
  86_400, 172_800, 604_800, 1_209_600, 2_629_800, 7_889_400, 15_778_800, 31_557_600, 63_115_200, 157_788_000
]

private func _chartTimeStep(range: Double, desired: Double) -> Double {
  var best = _chartTimeSteps[0]
  var bestScore = Double.infinity
  for candidate in _chartTimeSteps {
    let count = range / candidate
    let score = abs(count - desired)
    if score < bestScore { best = candidate; bestScore = score }
  }
  return best
}

/// Month/day (or hour/minute for short spans) text for a date axis value.
func _chartDefaultDateLabel(_ seconds: Double, range: Double) -> String {
  #if canImport(SwiftUIWebInternationalization)
  let date = Date(timeIntervalSince1970: seconds)
  if range < 172_800 { return Date.FormatStyle().hour().minute().format(date) }
  if range > 63_115_200 { return Date.FormatStyle().year().format(date) }
  return Date.FormatStyle().month(.abbreviated).day().format(date)
  #else
  let days = Int((seconds / 86_400).rounded(.down))
  let secondsOfDay = Int(seconds - Double(days) * 86_400)
  if range < 172_800 {
    let minute = (secondsOfDay % 3_600) / 60
    return "\(secondsOfDay / 3_600):\(minute < 10 ? "0" : "")\(minute)"
  }
  // Civil date from days since the epoch (proleptic Gregorian, UTC).
  let shifted = days + 719_468
  let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
  let dayOfEra = shifted - era * 146_097
  let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
  let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
  let monthPrime = (5 * dayOfYear + 2) / 153
  let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
  let month = monthPrime < 10 ? monthPrime + 3 : monthPrime - 9
  let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
  if range > 63_115_200 { return "\(year)" }
  let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return "\(names[month - 1]) \(day)"
  #endif
}

@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

// SwiftUIWebCharts deliberately depends only on the neutral Core module. The
// SVG realization below is an internal implementation detail: applications
// see SwiftUI-shaped marks and never a JavaScript/chart-library API.

public struct ChartValue: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case number(Double)
    case category(String)
  }

  public let label: String
  public let rawValue: String
  public let kind: Kind
  /// Set for values created from a `Date`, so axes can label them as times.
  var _isDate = false

  public init(label: String, rawValue: String, kind: Kind) {
    self.label = label
    self.rawValue = rawValue
    self.kind = kind
  }

  public var numericValue: Double? {
    if case .number(let value) = kind { return value }
    return nil
  }

  public static func value(_ label: String, _ value: Double) -> ChartValue {
    ChartValue(label: label, rawValue: _chartNumber(value), kind: .number(value))
  }
  public static func value(_ label: String, _ value: Float) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: Int) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: Int8) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: Int16) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: Int32) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: Int64) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: UInt) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: UInt8) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: UInt16) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: UInt32) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: UInt64) -> ChartValue { .value(label, Double(value)) }
  public static func value(_ label: String, _ value: Date) -> ChartValue {
    var result = ChartValue(label: label, rawValue: _chartNumber(value.timeIntervalSince1970), kind: .number(value.timeIntervalSince1970))
    result._isDate = true
    return result
  }
  public static func value(_ label: String, _ value: String) -> ChartValue {
    .init(label: label, rawValue: value, kind: .category(value))
  }
  public static func value(_ label: String, _ value: Substring) -> ChartValue {
    .value(label, String(value))
  }
  public static func value<V: Hashable>(_ label: String, _ value: V) -> ChartValue {
#if hasFeature(Embedded)
    // Embedded Swift 6.4 keeps the Hashable constraint available for source
    // compatibility, but does not expose hash(into:) / hashValue. Concrete
    // scalar overloads above retain their exact values. The generic erased
    // fallback therefore stays runtime-free instead of reintroducing
    // reflection or Foundation into the WASM.
    return .init(label: label, rawValue: "value", kind: .category("value"))
#else
    let raw = String(describing: value)
    return .init(label: label, rawValue: raw, kind: .category(raw))
#endif
  }
}

/// Swift Charts names this erased value `PlottableValue`; the alias keeps
/// source written for that API compiling while retaining a small value type.
public typealias PlottableValue = ChartValue

public struct ChartInterpolationMethod: Hashable, Sendable {
  enum Kind: Hashable, Sendable {
    case linear, monotone, stepStart, stepCenter, stepEnd, cardinal, catmullRom
  }
  let kind: Kind
  /// Cardinal tension, or Catmull-Rom alpha.
  let parameter: Double
  init(kind: Kind, parameter: Double = 0) { self.kind = kind; self.parameter = parameter }

  public static let linear = ChartInterpolationMethod(kind: .linear)
  public static let monotone = ChartInterpolationMethod(kind: .monotone)
  public static let stepStart = ChartInterpolationMethod(kind: .stepStart)
  public static let stepCenter = ChartInterpolationMethod(kind: .stepCenter)
  public static let stepEnd = ChartInterpolationMethod(kind: .stepEnd)
  public static let cardinal = ChartInterpolationMethod(kind: .cardinal, parameter: 0)
  public static func cardinal(tension: Double) -> ChartInterpolationMethod { ChartInterpolationMethod(kind: .cardinal, parameter: tension) }
  public static let catmullRom = ChartInterpolationMethod(kind: .catmullRom, parameter: 0.5)
  public static func catmullRom(alpha: Double) -> ChartInterpolationMethod { ChartInterpolationMethod(kind: .catmullRom, parameter: alpha) }
}
public typealias InterpolationMethod = ChartInterpolationMethod

public enum MarkStackingMethod: Hashable, Sendable {
  case standard
  case normalized
  case center
  case unstacked
}

public enum ChartAnnotationPosition: Hashable, Sendable {
  case top
  case bottom
  case leading
  case trailing
  case overlay
}
public typealias AnnotationPosition = ChartAnnotationPosition

public struct ChartMark: ChartContent {
  public enum Kind: Hashable, Sendable {
    case line
    case bar
    case area
    case point
    case rule
    case rectangle
  }

  public let kind: Kind
  public var x: ChartValue?
  public var y: ChartValue?
  public var xStart: ChartValue?
  public var xEnd: ChartValue?
  public var yStart: ChartValue?
  public var yEnd: ChartValue?
  public var stackingMethod: MarkStackingMethod
  public var interpolationMethod: ChartInterpolationMethod
  public var foregroundStyle: Color?
  public var foregroundStyleValue: ChartValue?
  public var opacity: Double
  public var symbolSize: Double
  public var lineWidth: Double
  public var annotationPosition: ChartAnnotationPosition?
  public var annotation: AnyView?
  var annotationSpacing: Double?
  var cornerRadius: Double?
  var foregroundGradient: LinearGradient?
  var seriesValue: ChartValue?
  var symbolValue: ChartValue?
  var symbolShape: BasicChartSymbolShape?
  var maskMarks: [ChartMark]?
  var rectWidth: MarkDimension?
  var rectHeight: MarkDimension?

  public init(kind: Kind, x: ChartValue? = nil, y: ChartValue? = nil) {
    self.kind = kind
    self.x = x; self.y = y
    xStart = nil; xEnd = nil; yStart = nil; yEnd = nil
    stackingMethod = .standard; interpolationMethod = .linear
    foregroundStyle = nil; foregroundStyleValue = nil
    opacity = 1; symbolSize = 36; lineWidth = 2
    annotationPosition = nil; annotation = nil
    annotationSpacing = nil; cornerRadius = nil; foregroundGradient = nil
    seriesValue = nil; symbolValue = nil; symbolShape = nil; maskMarks = nil
    rectWidth = nil; rectHeight = nil
  }

  public func _chartMarks() -> [ChartMark] { [self] }

  public func foregroundStyle(_ color: Color) -> ChartMark {
    var copy = self; copy.foregroundStyle = color; copy.foregroundGradient = nil; copy.foregroundStyleValue = nil; return copy
  }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> ChartMark {
    var copy = self
    // A linear gradient is kept as a gradient (the renderer emits an SVG
    // <linearGradient>); every other style resolves to its solid color.
    let gradient = AnyShapeStyle(style)._linearGradient
    copy.foregroundGradient = gradient
    copy.foregroundStyle = gradient?.gradient.stops.first?.color ?? Color(style._swiftUIWebCSSValue)
    copy.foregroundStyleValue = nil
    return copy
  }
  public func foregroundStyle(by value: ChartValue) -> ChartMark {
    var copy = self; copy.foregroundStyleValue = value; copy.foregroundStyle = nil; copy.foregroundGradient = nil; return copy
  }
  public func opacity(_ value: Double) -> ChartMark { var copy = self; copy.opacity = min(max(value, 0), 1); return copy }
  public func symbolSize(_ value: Double) -> ChartMark { var copy = self; copy.symbolSize = max(1, value); return copy }
  public func lineStyle(lineWidth: Double? = nil) -> ChartMark { var copy = self; if let lineWidth { copy.lineWidth = max(0.5, lineWidth) }; return copy }
  public func interpolationMethod(_ method: ChartInterpolationMethod) -> ChartMark { var copy = self; copy.interpolationMethod = method; return copy }
  public func stackingMethod(_ method: MarkStackingMethod) -> ChartMark { var copy = self; copy.stackingMethod = method; return copy }
  @MainActor public func annotation<C: View>(position: ChartAnnotationPosition = .top, alignment: Alignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> C) -> ChartMark {
    var copy = self; copy.annotationPosition = position; copy.annotation = AnyView(content()); copy.annotationSpacing = spacing; return copy
  }
}

/// Chart marks are also `View`s so that `ForEach`, whose content closure is a
/// `@ViewBuilder`, accepts them exactly as Swift Charts' `ForEach` does. They
/// are never rendered as views: a `Chart` collects `_chartMarks()` instead.
public protocol ChartContent: View where Body == Never {
  func _chartMarks() -> [ChartMark]
}

extension ChartContent {
  public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.styles["display"] = "none"
    return node
  }
}

@MainActor @preconcurrency @resultBuilder public enum ChartContentBuilder {
  public static func buildBlock() -> ChartContentGroup { ChartContentGroup([]) }
  public static func buildBlock<C: ChartContent>(_ content: C) -> C { content }
  public static func buildBlock<C0: ChartContent, C1: ChartContent>(_ c0: C0, _ c1: C1) -> ChartContentGroup { ChartContentGroup([AnyChartContent(c0), AnyChartContent(c1)]) }
  public static func buildBlock<C0: ChartContent, C1: ChartContent, C2: ChartContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> ChartContentGroup { ChartContentGroup([AnyChartContent(c0), AnyChartContent(c1), AnyChartContent(c2)]) }
  public static func buildBlock<C0: ChartContent, C1: ChartContent, C2: ChartContent, C3: ChartContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> ChartContentGroup { ChartContentGroup([AnyChartContent(c0), AnyChartContent(c1), AnyChartContent(c2), AnyChartContent(c3)]) }
  public static func buildBlock<C0: ChartContent, C1: ChartContent, C2: ChartContent, C3: ChartContent, C4: ChartContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> ChartContentGroup { ChartContentGroup([AnyChartContent(c0), AnyChartContent(c1), AnyChartContent(c2), AnyChartContent(c3), AnyChartContent(c4)]) }
  public static func buildBlock<C0: ChartContent, C1: ChartContent, C2: ChartContent, C3: ChartContent, C4: ChartContent, C5: ChartContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> ChartContentGroup { ChartContentGroup([AnyChartContent(c0), AnyChartContent(c1), AnyChartContent(c2), AnyChartContent(c3), AnyChartContent(c4), AnyChartContent(c5)]) }
  public static func buildBlock<C0: ChartContent, C1: ChartContent, C2: ChartContent, C3: ChartContent, C4: ChartContent, C5: ChartContent, C6: ChartContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> ChartContentGroup { ChartContentGroup([AnyChartContent(c0), AnyChartContent(c1), AnyChartContent(c2), AnyChartContent(c3), AnyChartContent(c4), AnyChartContent(c5), AnyChartContent(c6)]) }
  public static func buildEither<TrueContent: ChartContent, FalseContent: ChartContent>(first: TrueContent) -> _ChartConditionalContent<TrueContent, FalseContent> { .first(first) }
  public static func buildEither<TrueContent: ChartContent, FalseContent: ChartContent>(second: FalseContent) -> _ChartConditionalContent<TrueContent, FalseContent> { .second(second) }
  public static func buildOptional<C: ChartContent>(_ component: C?) -> _ChartConditionalContent<C, ChartContentGroup> { component.map { .first($0) } ?? .second(ChartContentGroup([])) }
  public static func buildArray<C: ChartContent>(_ components: [C]) -> ChartContentGroup { ChartContentGroup(components) }
}

public struct ChartContentGroup: ChartContent {
  private let content: [AnyChartContent]
  public init(_ content: [AnyChartContent]) { self.content = content }
  fileprivate init<C: ChartContent>(_ content: [C]) {
    var erased: [AnyChartContent] = []
    erased.reserveCapacity(content.count)
    for value in content { erased.append(AnyChartContent(value)) }
    self.content = erased
  }
  public func _chartMarks() -> [ChartMark] { content.flatMap { $0._chartMarks() } }
}

public struct AnyChartContent: ChartContent {
  private let makeMarks: () -> [ChartMark]
  public init<C: ChartContent>(_ content: C) { makeMarks = content._chartMarks }
  public func _chartMarks() -> [ChartMark] { makeMarks() }
}

public enum _ChartConditionalContent<TrueContent: ChartContent, FalseContent: ChartContent>: ChartContent {
  case first(TrueContent)
  case second(FalseContent)
  public func _chartMarks() -> [ChartMark] {
    switch self { case .first(let value): return value._chartMarks(); case .second(let value): return value._chartMarks() }
  }
}

public struct LineMark: ChartContent {
  private var mark: ChartMark
  public init(x: ChartValue, y: ChartValue) { mark = ChartMark(kind: .line, x: x, y: y) }
  /// Marks sharing a `series` value are joined into one line.
  public init(x: ChartValue, y: ChartValue, series: ChartValue) { mark = ChartMark(kind: .line, x: x, y: y); mark.seriesValue = series }
  public func _chartMarks() -> [ChartMark] { mark._chartMarks() }
  public func foregroundStyle(_ color: Color) -> LineMark { modifying { $0 = $0.foregroundStyle(color) } }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> LineMark { modifying { $0 = $0.foregroundStyle(style) } }
  public func foregroundStyle(by value: ChartValue) -> LineMark { modifying { $0 = $0.foregroundStyle(by: value) } }
  public func interpolationMethod(_ value: ChartInterpolationMethod) -> LineMark { modifying { $0 = $0.interpolationMethod(value) } }
  public func lineStyle(lineWidth: Double? = nil) -> LineMark { modifying { $0 = $0.lineStyle(lineWidth: lineWidth) } }
  public func opacity(_ value: Double) -> LineMark { modifying { $0 = $0.opacity(value) } }
  @MainActor public func annotation<C: View>(position: ChartAnnotationPosition = .top, alignment: Alignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> C) -> LineMark { modifying { $0 = $0.annotation(position: position, alignment: alignment, spacing: spacing, content: content) } }
  private func modifying(_ body: (inout ChartMark) -> Void) -> LineMark { var copy = self; body(&copy.mark); return copy }
}

public struct BarMark: ChartContent {
  private var mark: ChartMark
  public init(x: ChartValue, y: ChartValue) { mark = ChartMark(kind: .bar, x: x, y: y) }
  public func _chartMarks() -> [ChartMark] { mark._chartMarks() }
  public func foregroundStyle(_ color: Color) -> BarMark { modifying { $0 = $0.foregroundStyle(color) } }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> BarMark { modifying { $0 = $0.foregroundStyle(style) } }
  public func foregroundStyle(by value: ChartValue) -> BarMark { modifying { $0 = $0.foregroundStyle(by: value) } }
  public func stackingMethod(_ value: MarkStackingMethod) -> BarMark { modifying { $0 = $0.stackingMethod(value) } }
  public func cornerRadius(_ radius: Double, style: RoundedCornerStyle = .circular) -> BarMark { modifying { $0.cornerRadius = max(0, radius) } }
  public func opacity(_ value: Double) -> BarMark { modifying { $0 = $0.opacity(value) } }
  @MainActor public func annotation<C: View>(position: ChartAnnotationPosition = .top, alignment: Alignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> C) -> BarMark { modifying { $0 = $0.annotation(position: position, alignment: alignment, spacing: spacing, content: content) } }
  private func modifying(_ body: (inout ChartMark) -> Void) -> BarMark { var copy = self; body(&copy.mark); return copy }
}

public struct AreaMark: ChartContent {
  private var mark: ChartMark
  public init(x: ChartValue, y: ChartValue) { mark = ChartMark(kind: .area, x: x, y: y) }
  public init(x: ChartValue, yStart: ChartValue, yEnd: ChartValue) { mark = ChartMark(kind: .area, x: x, y: nil); mark.yStart = yStart; mark.yEnd = yEnd }
  public init(x: ChartValue, y: ChartValue, series: ChartValue) { mark = ChartMark(kind: .area, x: x, y: y); mark.seriesValue = series }
  public init(x: ChartValue, yStart: ChartValue, yEnd: ChartValue, series: ChartValue) { mark = ChartMark(kind: .area, x: x, y: nil); mark.yStart = yStart; mark.yEnd = yEnd; mark.seriesValue = series }
  public func _chartMarks() -> [ChartMark] { mark._chartMarks() }
  public func foregroundStyle(_ color: Color) -> AreaMark { modifying { $0 = $0.foregroundStyle(color) } }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> AreaMark { modifying { $0 = $0.foregroundStyle(style) } }
  public func foregroundStyle(by value: ChartValue) -> AreaMark { modifying { $0 = $0.foregroundStyle(by: value) } }
  public func stackingMethod(_ value: MarkStackingMethod) -> AreaMark { modifying { $0 = $0.stackingMethod(value) } }
  public func opacity(_ value: Double) -> AreaMark { modifying { $0 = $0.opacity(value) } }
  public func interpolationMethod(_ value: ChartInterpolationMethod) -> AreaMark { modifying { $0 = $0.interpolationMethod(value) } }
  @MainActor public func annotation<C: View>(position: ChartAnnotationPosition = .top, alignment: Alignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> C) -> AreaMark { modifying { $0 = $0.annotation(position: position, alignment: alignment, spacing: spacing, content: content) } }
  private func modifying(_ body: (inout ChartMark) -> Void) -> AreaMark { var copy = self; body(&copy.mark); return copy }
}

public struct PointMark: ChartContent {
  private var mark: ChartMark
  public init(x: ChartValue, y: ChartValue) { mark = ChartMark(kind: .point, x: x, y: y) }
  public func _chartMarks() -> [ChartMark] { mark._chartMarks() }
  public func foregroundStyle(_ color: Color) -> PointMark { modifying { $0 = $0.foregroundStyle(color) } }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> PointMark { modifying { $0 = $0.foregroundStyle(style) } }
  public func foregroundStyle(by value: ChartValue) -> PointMark { modifying { $0 = $0.foregroundStyle(by: value) } }
  public func symbolSize(_ value: Double) -> PointMark { modifying { $0 = $0.symbolSize(value) } }
  public func opacity(_ value: Double) -> PointMark { modifying { $0 = $0.opacity(value) } }
  @MainActor public func annotation<C: View>(position: ChartAnnotationPosition = .top, alignment: Alignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> C) -> PointMark { modifying { $0 = $0.annotation(position: position, alignment: alignment, spacing: spacing, content: content) } }
  private func modifying(_ body: (inout ChartMark) -> Void) -> PointMark { var copy = self; body(&copy.mark); return copy }
}

public struct RuleMark: ChartContent {
  private var mark: ChartMark
  public init(y: ChartValue) { mark = ChartMark(kind: .rule, y: y) }
  public init(x: ChartValue) { mark = ChartMark(kind: .rule, x: x) }
  public func _chartMarks() -> [ChartMark] { mark._chartMarks() }
  public func foregroundStyle(_ color: Color) -> RuleMark { modifying { $0 = $0.foregroundStyle(color) } }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> RuleMark { modifying { $0 = $0.foregroundStyle(style) } }
  public func lineStyle(lineWidth: Double? = nil) -> RuleMark { modifying { $0 = $0.lineStyle(lineWidth: lineWidth) } }
  public func opacity(_ value: Double) -> RuleMark { modifying { $0 = $0.opacity(value) } }
  @MainActor public func annotation<C: View>(position: ChartAnnotationPosition = .top, alignment: Alignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> C) -> RuleMark { modifying { $0 = $0.annotation(position: position, alignment: alignment, spacing: spacing, content: content) } }
  private func modifying(_ body: (inout ChartMark) -> Void) -> RuleMark { var copy = self; body(&copy.mark); return copy }
}

/// A filled rectangle. Spans the plot's full height or width on an axis for
/// which no range is given, so `RectangleMark(xStart:xEnd:)` is a band.
public struct RectangleMark: ChartContent {
  private var mark: ChartMark
  private init() { mark = ChartMark(kind: .rectangle) }
  /// A rectangle centered on `x`/`y`.
  public init(x: ChartValue, y: ChartValue, width: MarkDimension = .automatic, height: MarkDimension = .automatic) {
    self.init(); mark.x = x; mark.y = y; mark.rectWidth = width; mark.rectHeight = height
  }
  public init(xStart: ChartValue, xEnd: ChartValue, yStart: ChartValue, yEnd: ChartValue) {
    self.init(); mark.xStart = xStart; mark.xEnd = xEnd; mark.yStart = yStart; mark.yEnd = yEnd
  }
  public init(xStart: ChartValue, xEnd: ChartValue, y: ChartValue, height: MarkDimension = .automatic) {
    self.init(); mark.xStart = xStart; mark.xEnd = xEnd; mark.y = y; mark.rectHeight = height
  }
  public init(x: ChartValue, yStart: ChartValue, yEnd: ChartValue, width: MarkDimension = .automatic) {
    self.init(); mark.x = x; mark.yStart = yStart; mark.yEnd = yEnd; mark.rectWidth = width
  }
  public init(xStart: ChartValue, xEnd: ChartValue) { self.init(); mark.xStart = xStart; mark.xEnd = xEnd }
  public init(yStart: ChartValue, yEnd: ChartValue) { self.init(); mark.yStart = yStart; mark.yEnd = yEnd }
  public func _chartMarks() -> [ChartMark] { mark._chartMarks() }
  public func foregroundStyle(_ color: Color) -> RectangleMark { modifying { $0 = $0.foregroundStyle(color) } }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> RectangleMark { modifying { $0 = $0.foregroundStyle(style) } }
  public func foregroundStyle(by value: ChartValue) -> RectangleMark { modifying { $0 = $0.foregroundStyle(by: value) } }
  public func opacity(_ value: Double) -> RectangleMark { modifying { $0 = $0.opacity(value) } }
  public func cornerRadius(_ radius: Double, style: RoundedCornerStyle = .circular) -> RectangleMark { modifying { $0.cornerRadius = max(0, radius) } }
  @MainActor public func annotation<C: View>(position: ChartAnnotationPosition = .top, alignment: Alignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> C) -> RectangleMark { modifying { $0 = $0.annotation(position: position, alignment: alignment, spacing: spacing, content: content) } }
  private func modifying(_ body: (inout ChartMark) -> Void) -> RectangleMark { var copy = self; body(&copy.mark); return copy }
}

/// Width or height of a mark such as `RectangleMark`.
public struct MarkDimension: Hashable, Sendable {
  enum Kind: Hashable, Sendable { case automatic, fixed(Double), ratio(Double), inset(Double) }
  let kind: Kind
  public static let automatic = MarkDimension(kind: .automatic)
  public static func fixed(_ value: Double) -> MarkDimension { MarkDimension(kind: .fixed(value)) }
  public static func ratio(_ value: Double) -> MarkDimension { MarkDimension(kind: .ratio(value)) }
  public static func inset(_ value: Double) -> MarkDimension { MarkDimension(kind: .inset(value)) }
}

public protocol ChartSymbolShape {
  var _basicShape: BasicChartSymbolShape { get }
}

/// The built-in symbol shapes (`.symbol(.circle)`, `.symbol(by:)`).
public struct BasicChartSymbolShape: ChartSymbolShape, Hashable, Sendable {
  enum Kind: Hashable, Sendable { case circle, square, triangle, diamond, pentagon, plus, cross, asterisk }
  let kind: Kind
  public static let circle = BasicChartSymbolShape(kind: .circle)
  public static let square = BasicChartSymbolShape(kind: .square)
  public static let triangle = BasicChartSymbolShape(kind: .triangle)
  public static let diamond = BasicChartSymbolShape(kind: .diamond)
  public static let pentagon = BasicChartSymbolShape(kind: .pentagon)
  public static let plus = BasicChartSymbolShape(kind: .plus)
  public static let cross = BasicChartSymbolShape(kind: .cross)
  public static let asterisk = BasicChartSymbolShape(kind: .asterisk)
  public var _basicShape: BasicChartSymbolShape { self }
  static let cycle: [BasicChartSymbolShape] = [.circle, .square, .triangle, .diamond, .pentagon, .plus, .cross, .asterisk]
}

/// Primitive values a chart can plot.
public protocol Plottable {
  func _chartValue(label: String) -> ChartValue
  static func _fromChartValue(_ value: ChartValue) -> Self?
}
extension Double: Plottable {
  public func _chartValue(label: String) -> ChartValue { .value(label, self) }
  public static func _fromChartValue(_ value: ChartValue) -> Double? { value.numericValue }
}
extension Float: Plottable {
  public func _chartValue(label: String) -> ChartValue { .value(label, self) }
  public static func _fromChartValue(_ value: ChartValue) -> Float? { value.numericValue.map { Float($0) } }
}
extension Int: Plottable {
  public func _chartValue(label: String) -> ChartValue { .value(label, self) }
  /// nil for a value Int cannot hold: past 2^31 in the browser build, where Int is 32 bits.
  public static func _fromChartValue(_ value: ChartValue) -> Int? { value.numericValue.flatMap { Int(exactly: $0.rounded()) } }
}
extension String: Plottable {
  public func _chartValue(label: String) -> ChartValue { .value(label, self) }
  public static func _fromChartValue(_ value: ChartValue) -> String? { value.rawValue }
}
extension Date: Plottable {
  public func _chartValue(label: String) -> ChartValue { .value(label, self) }
  public static func _fromChartValue(_ value: ChartValue) -> Date? {
    value.numericValue.map { Date(timeIntervalSince1970: $0) }
  }
}

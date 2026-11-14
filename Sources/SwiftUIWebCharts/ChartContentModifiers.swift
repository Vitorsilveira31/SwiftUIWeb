@_spi(Renderer) import SwiftUIWebCore

// Swift Charts' `ChartContent` modifiers. They are written once against the
// protocol, so they apply to marks, `ForEach`, groups and the results of other
// modifiers alike. Each returns a `_ModifiedChartContent` that rewrites the
// marks of its base; nothing is erased or reflected, which keeps the file
// buildable for Embedded Swift.

public struct _ModifiedChartContent<Base: ChartContent>: ChartContent {
  let base: Base
  let transform: (inout ChartMark) -> Void

  public func _chartMarks() -> [ChartMark] {
    var result: [ChartMark] = []
    for mark in base._chartMarks() {
      var copy = mark
      transform(&copy)
      result.append(copy)
    }
    return result
  }
}

extension ChartContent {
  func _modified(_ transform: @escaping (inout ChartMark) -> Void) -> _ModifiedChartContent<Self> {
    _ModifiedChartContent(base: self, transform: transform)
  }

  public func foregroundStyle(_ color: Color) -> _ModifiedChartContent<Self> {
    _modified { $0 = $0.foregroundStyle(color) }
  }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> _ModifiedChartContent<Self> {
    _modified { $0 = $0.foregroundStyle(style) }
  }
  public func foregroundStyle(by value: ChartValue) -> _ModifiedChartContent<Self> {
    _modified { $0 = $0.foregroundStyle(by: value) }
  }
  public func opacity(_ value: Double) -> _ModifiedChartContent<Self> {
    _modified { $0 = $0.opacity(value) }
  }
  public func lineStyle(_ style: StrokeStyle) -> _ModifiedChartContent<Self> {
    _modified { $0.lineWidth = max(0.5, style.lineWidth) }
  }
  public func interpolationMethod(_ method: ChartInterpolationMethod) -> _ModifiedChartContent<Self> {
    _modified { $0.interpolationMethod = method }
  }
  public func symbol(by value: ChartValue) -> _ModifiedChartContent<Self> {
    _modified { $0.symbolValue = value }
  }
  public func symbol<S: ChartSymbolShape>(_ symbol: S) -> _ModifiedChartContent<Self> {
    let basic = symbol._basicShape
    return _modified { $0.symbolShape = basic }
  }
  public func symbolSize(_ value: Double) -> _ModifiedChartContent<Self> {
    _modified { $0 = $0.symbolSize(value) }
  }
  public func cornerRadius(_ radius: Double, style: RoundedCornerStyle = .circular) -> _ModifiedChartContent<Self> {
    // Rounded corners are circular; the continuous style is visually close.
    _modified { $0.cornerRadius = max(0, radius) }
  }
  public func annotation<C: View>(position: ChartAnnotationPosition = .top, alignment: Alignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> C) -> _ModifiedChartContent<Self> {
    let view = AnyView(content())
    return _modified {
      $0.annotationPosition = position
      $0.annotation = view
      $0.annotationSpacing = spacing
    }
  }
  /// Clips the marks to the marks of `content`: only where the mask content
  /// is painted do the marks show (an SVG luminance mask).
  public func mask<C: ChartContent>(@ChartContentBuilder content: () -> C) -> _ModifiedChartContent<Self> {
    let maskMarks = content()._chartMarks()
    return _modified { $0.maskMarks = maskMarks }
  }
}

extension ForEach: ChartContent where Content: ChartContent {
  public func _chartMarks() -> [ChartMark] {
    var marks: [ChartMark] = []
    for element in data { marks.append(contentsOf: content(element)._chartMarks()) }
    return marks
  }
}

// `ForEach`'s own initializers take a `@ViewBuilder`, which cannot express an
// `if` or several marks as chart content. These overloads take a
// `@ChartContentBuilder`; being declared for `Content: ChartContent` they are
// the more specialized candidates, so a chart's `ForEach` resolves to them.
// They forward through helpers declared where `Content` is only a `View`, in
// which context the overloads below are not applicable and the original
// initializers are the ones called.
extension ForEach {
  @MainActor fileprivate static func _forwarded(_ data: Data, id: KeyPath<Data.Element, ID>, content: @escaping (Data.Element) -> Content) -> ForEach {
    ForEach(_forwarding: data, id: id, content: content)
  }
  @MainActor fileprivate static func _forwarded(_ data: Data, id: @escaping (Data.Element) -> ID, content: @escaping (Data.Element) -> Content) -> ForEach {
    ForEach(_forwarding: data, id: id, content: content)
  }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
  fileprivate static func _forwarded(_ data: Data, content: @escaping (Data.Element) -> Content) -> ForEach {
    ForEach(data, content: content)
  }
}

extension ForEach where Content: ChartContent {
  @MainActor public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ChartContentBuilder content: @escaping (Data.Element) -> Content) {
    self = Self._forwarded(data, id: id, content: content)
  }

  @MainActor public init(_ data: Data, id: @escaping (Data.Element) -> ID, @ChartContentBuilder content: @escaping (Data.Element) -> Content) {
    self = Self._forwarded(data, id: id, content: content)
  }
}

extension ForEach where Content: ChartContent, Data.Element: Identifiable, ID == Data.Element.ID {
  public init(_ data: Data, @ChartContentBuilder content: @escaping (Data.Element) -> Content) {
    self = Self._forwarded(data, content: content)
  }
}

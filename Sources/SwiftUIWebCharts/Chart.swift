@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

public enum ChartLegendPosition: Hashable, Sendable { case automatic, top, bottom, leading, trailing, hidden }

public enum ChartSelectionAxis: Hashable, Sendable { case x, y }

public struct ChartScaleDomain: Hashable, Sendable {
  public let lowerBound: ChartValue
  public let upperBound: ChartValue
  public init(lowerBound: ChartValue, upperBound: ChartValue) { self.lowerBound = lowerBound; self.upperBound = upperBound }
}

public struct Chart<Content: ChartContent>: View {
  public typealias Body = Never
  private let markProvider: () -> [ChartMark]
  private var configuration: _ChartConfiguration

  public init(@ChartContentBuilder content: @escaping () -> Content) {
    markProvider = { content()._chartMarks() }
    configuration = _ChartConfiguration()
  }

  public init<Data: RandomAccessCollection>(_ data: Data, @ChartContentBuilder content: @escaping (Data.Element) -> Content) {
    markProvider = { data.flatMap { content($0)._chartMarks() } }
    configuration = _ChartConfiguration()
  }

  public init<Data: RandomAccessCollection, ID: Hashable>(_ data: Data, id: KeyPath<Data.Element, ID>, @ChartContentBuilder content: @escaping (Data.Element) -> Content) {
    markProvider = { data.flatMap { content($0)._chartMarks() } }
    configuration = _ChartConfiguration()
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    let marks = markProvider(), configuration = configuration
    // A chart takes the space it is offered, as Swift Charts does, and is drawn at that size: the reader reports the
    // size the host gave it (a chart offered nothing is 640x320). Until the host has measured it, it is drawn at that
    // ideal size and scaled to fit.
    return GeometryReader { proxy in
      _ChartPlot(model: _ChartModel(marks: marks, configuration: configuration, size: proxy.size))
    }
    .frame(idealWidth: 640, idealHeight: 320)
    ._render(in: context)
  }

  public func chartXAxis(_ marks: AxisMarks) -> Chart {
    modifying { if marks.isCustom { $0.xAxisCustom = [marks] }; $0.xAxis = marks }
  }
  public func chartYAxis(_ marks: AxisMarks) -> Chart {
    modifying { if marks.isCustom { $0.yAxisCustom = [marks] }; $0.yAxis = marks }
  }
  /// Replaces the x axis marks with those built by `content`.
  public func chartXAxis<C: AxisContent>(@AxisContentBuilder content: () -> C) -> Chart {
    let list = content()._axisMarksList()
    return modifying { $0.xAxisCustom = list; $0.xAxis = .visible }
  }
  /// Replaces the y axis marks with those built by `content`.
  public func chartYAxis<C: AxisContent>(@AxisContentBuilder content: () -> C) -> Chart {
    let list = content()._axisMarksList()
    return modifying { $0.yAxisCustom = list; $0.yAxis = .visible }
  }
  public func chartXAxisLabel(_ label: String) -> Chart {
    modifying { $0.xAxisLabel = label }
  }
  public func chartXAxisLabel(_ label: Text) -> Chart { chartXAxisLabel(label.value) }
  public func chartYAxisLabel(_ label: String) -> Chart {
    modifying { $0.yAxisLabel = label }
  }
  public func chartYAxisLabel(_ label: Text) -> Chart { chartYAxisLabel(label.value) }
  public func chartXScale<V: Comparable>(domain: ClosedRange<V>) -> Chart {
    modifying { $0.xScale = ChartScaleDomain(lowerBound: _chartValue(domain.lowerBound), upperBound: _chartValue(domain.upperBound)) }
  }
  public func chartYScale<V: Comparable>(domain: ClosedRange<V>) -> Chart {
    modifying { $0.yScale = ChartScaleDomain(lowerBound: _chartValue(domain.lowerBound), upperBound: _chartValue(domain.upperBound)) }
  }
  public func chartXScale(domain: AutomaticScaleDomain) -> Chart {
    modifying { $0.xAutomaticDomain = domain }
  }
  public func chartYScale(domain: AutomaticScaleDomain) -> Chart {
    modifying { $0.yAutomaticDomain = domain }
  }
  /// `.chartLegend(.hidden)`: the visibility spelling.
  public func chartLegend(_ visibility: Visibility) -> Chart {
    modifying { $0.legendPosition = visibility == .hidden ? .hidden : .automatic }
  }
  public func chartLegend(position: ChartLegendPosition = .automatic, alignment: Alignment = .center, spacing: Double? = nil) -> Chart {
    modifying { $0.legendPosition = position }
  }
  public func chartForegroundStyleScale(_ scale: [String: Color]) -> Chart {
    modifying { $0.foregroundScale = scale }
  }
  public func chartForegroundStyleScale(domain: [String], range: [Color]) -> Chart {
    var mapping: [String: Color] = .init()
    for (index, value) in domain.enumerated() where index < range.count { mapping[value] = range[index] }
    return modifying { $0.foregroundScale = mapping }
  }
  public func chartXSelection<V: Hashable>(value: Binding<V?>) -> Chart {
    modifying { config in
      config.selectionAxis = .x
      config.selection = { chartValue in
        guard let decoded: V = _decodeChartValue(chartValue) else { return }
        value.wrappedValue = decoded
      }
    }
  }
  public func chartYSelection<V: Hashable>(value: Binding<V?>) -> Chart {
    modifying { config in
      config.selectionAxis = .y
      config.selection = { chartValue in
        guard let decoded: V = _decodeChartValue(chartValue) else { return }
        value.wrappedValue = decoded
      }
    }
  }
  public func chartSelection<V: Hashable>(value: Binding<V?>, axis: ChartSelectionAxis = .x) -> Chart {
    axis == .x ? chartXSelection(value: value) : chartYSelection(value: value)
  }

  private func modifying(_ body: (inout _ChartConfiguration) -> Void) -> Chart {
    var copy = self; body(&copy.configuration); return copy
  }
}

struct _ChartConfiguration {
  var xAxis = AxisMarks.automatic
  var yAxis = AxisMarks.automatic
  var xAxisCustom: [AxisMarks]?
  var yAxisCustom: [AxisMarks]?
  var xAxisLabel: String?
  var yAxisLabel: String?
  var xScale: ChartScaleDomain?
  var yScale: ChartScaleDomain?
  var xAutomaticDomain: AutomaticScaleDomain?
  var yAutomaticDomain: AutomaticScaleDomain?
  var legendPosition = ChartLegendPosition.automatic
  var foregroundScale: [String: Color] = .init()
  var selectionAxis: ChartSelectionAxis?
  var selection: ((ChartValue) -> Void)?
}

struct _ChartModel {
  let marks: [ChartMark]
  let configuration: _ChartConfiguration
  /// The size the host laid the chart out at; zero before it has measured it.
  var size: CGSize = CGSize(width: 0, height: 0)
}

/// The chart drawn for one size (see `Chart._render`).
struct _ChartPlot: View {
  typealias Body = Never
  let model: _ChartModel
  @MainActor func _render(in context: _RenderContext) -> _RenderNode {
    let node = _SVGChartRenderer().render(model, context: context)
    // `chartPlotStyle` wraps the rendered plot in the caller's view tree.
    guard let style = context.environment[_ChartPlotStyleKey.self].apply else { return node }
    return AnyView(style(ChartPlotContent(rendered: node)))._render(in: context.child(_FiberKey("chart-plot-style")))
  }
}

/// Internal renderer seam. Additional backends (for example Canvas) can
/// conform without changing the public Chart/Mark API.
@MainActor @preconcurrency
protocol _ChartRenderer {
  @MainActor func render(_ model: _ChartModel, context: _RenderContext) -> _RenderNode
}

struct _ChartLayout {
  let width: Double
  /// Room above the plot: more when the legend is drawn there.
  let top: Double
  /// The plot's margins: the y axis labels take the wider one, on the trailing side as in Swift Charts.
  let left: Double
  let right: Double
  /// Whether the y axis sits on the plot's leading side (`AxisMarks(position: .leading)`).
  let yAxisLeading: Bool
  let plotHeight: Double
  /// Room under the plot for axis labels; grows when labels are views.
  let bottom: Double
  /// Whether this is the size the host laid the chart out at, rather than the 640 pt wide fallback.
  let measured: Bool
  init(bottom: Double = 42, size: CGSize = CGSize(width: 0, height: 0), legendAbove: Bool = false, yAxisLeading: Bool = false) {
    self.bottom = bottom
    self.yAxisLeading = yAxisLeading
    left = yAxisLeading ? 52 : 16
    right = yAxisLeading ? 16 : 52
    top = legendAbove ? 32 : 16
    measured = size.width > 0 && size.height > 0
    width = measured ? Double(size.width) : 640
    plotHeight = measured ? max(Double(size.height) - top - bottom, 24) : 278 - top
  }
  var height: Double { top + plotHeight + bottom }
  var plotWidth: Double { width - left - right }
}

struct _ChartDomain {
  let lower: Double
  let upper: Double
  let categories: [String]
  let categoryMode: Bool
  let label: String
  var isDate = false
  var reversed = false

  /// Whether a categorical domain lists `value`. A numeric domain, or a missing value, always fits.
  func knows(_ value: ChartValue?) -> Bool {
    guard categoryMode, let value else { return true }
    return categories.contains(value.rawValue)
  }

  @MainActor func position(_ value: ChartValue) -> Double {
    if categoryMode {
      let index = categories.firstIndex(of: value.rawValue) ?? 0
      return Double(index)
    }
    return value.numericValue ?? 0
  }

  /// 0...1 along the axis (1 - that when the scale is reversed).
  @MainActor func fraction(_ value: ChartValue) -> Double {
    let raw = position(value)
    let span = max(upper - lower, 0.000001)
    let fraction = (raw - lower) / span
    return reversed ? 1 - fraction : fraction
  }
}

struct _ChartMarkBox {
  var minX: Double, minY: Double, maxX: Double, maxY: Double
  var centerX: Double { (minX + maxX) / 2 }
  var centerY: Double { (minY + maxY) / 2 }
}

@MainActor struct _ChartRenderEnvironment {
  let layout: _ChartLayout
  let xDomain: _ChartDomain
  let yDomain: _ChartDomain
  let xScale: (ChartValue) -> Double
  let yScale: (ChartValue) -> Double
  let selection: ((ChartValue) -> Void)?
  let selectionAxis: ChartSelectionAxis?
  let symbolOrder: [String]
  let context: _RenderContext
}

struct _SVGChartRenderer: _ChartRenderer {
  private let palette: [Color] = [.blue, .orange, .green, .purple, .red, .yellow]

  @MainActor func render(_ model: _ChartModel, context: _RenderContext) -> _RenderNode {
    let configuration = model.configuration
    let xDomain = domain(for: model.marks, axis: .x, explicit: configuration.xScale, automatic: configuration.xAutomaticDomain)
    let yDomain = domain(for: model.marks, axis: .y, explicit: configuration.yScale, automatic: configuration.yAutomaticDomain)
    // Custom axis marks are evaluated up front: view-valued labels decide
    // how much room the plot leaves below itself.
    let xAxis = configuration.xAxisCustom.map { resolveAxis($0, domain: xDomain) }
    let yAxis = configuration.yAxisCustom.map { resolveAxis($0, domain: yDomain) }
    let legendAbove = configuration.legendPosition != .hidden && configuration.legendPosition != .bottom
      && configuration.legendPosition != .trailing && model.marks.contains { $0.foregroundStyleValue != nil }
    let layout = _ChartLayout(
      bottom: xAxis?.hasViewLabels == true ? 104 : 42, size: model.size, legendAbove: legendAbove,
      yAxisLeading: configuration.yAxisCustom?.first?.position == .leading
    )
    let xScale = { (value: ChartValue) -> Double in
      layout.left + xDomain.fraction(value) * layout.plotWidth
    }
    let yScale = { (value: ChartValue) -> Double in
      layout.top + layout.plotHeight - yDomain.fraction(value) * layout.plotHeight
    }
    var symbolOrder: [String] = []
    var seenSymbols = Set<String>()
    for mark in model.marks {
      if let value = mark.symbolValue, seenSymbols.insert(value.rawValue).inserted { symbolOrder.append(value.rawValue) }
    }
    let env = _ChartRenderEnvironment(layout: layout, xDomain: xDomain, yDomain: yDomain, xScale: xScale, yScale: yScale, selection: configuration.selection, selectionAxis: configuration.selectionAxis, symbolOrder: symbolOrder, context: context)

    let root = _RenderNode.element("div")
    root.classes = ["data-chart"]
    root.attributes["role"] = "img"
    root.attributes["aria-label"] = chartLabel(model.marks)
    root.styles["width"] = "100%"
    if layout.measured {
      root.styles["height"] = "100%"
    } else {
      root.styles["max-width"] = "640px"
      // Stable intrinsic fallback. Explicit SwiftUI frame width/height still win
      // because frame modifiers are applied to this semantic root afterwards.
      root.styles["aspect-ratio"] = layout.bottom == 42 ? "2 / 1" : "\(_chartNumber(layout.width)) / \(_chartNumber(layout.height))"
    }
    root.styles["font-family"] = "system-ui, sans-serif"

    let svg = _RenderNode.element("svg")
    svg.attributes["xmlns"] = "http://www.w3.org/2000/svg"
    svg.attributes["viewBox"] = "0 0 \(_chartNumber(layout.width)) \(_chartNumber(layout.height))"
    svg.attributes["preserveAspectRatio"] = "xMidYMid meet"
    // Keep the viewBox as the deterministic chart coordinate system, but let
    // SwiftUI's frame/proposal own the actual rendered size. Fixed SVG pixel
    // attributes made framed charts overflow or appear vertically squashed.
    svg.attributes["width"] = "100%"
    svg.attributes["height"] = "100%"
    svg.styles["display"] = "block"
    // Annotations of marks at the plot's edge extend past the viewBox.
    svg.styles["overflow"] = "visible"
    svg.classes = ["chart-svg"]
    svg.children.append(contentsOf: axes(env: env, config: configuration, xAxis: xAxis, yAxis: yAxis))

    var nextPalette = 0
    var legendValues: [(String, Color)] = []
    svg.children.append(contentsOf: renderMarks(model.marks, env: env, styleValues: configuration.foregroundScale, forced: nil, nextPalette: &nextPalette, legendValues: &legendValues))
    if configuration.legendPosition != .hidden && !legendValues.isEmpty {
      let legend = _RenderNode.element("g")
      legend.attributes["data-chart-legend"] = "true"
      if let legendLabel = model.marks.compactMap({ $0.foregroundStyleValue?.label }).first, !legendLabel.isEmpty {
        legend.attributes["aria-label"] = legendLabel
      }
      let legendX = configuration.legendPosition == .trailing ? layout.width - 180 : layout.left
      let legendY = configuration.legendPosition == .bottom ? layout.height - 12 : 14
      legend.attributes["transform"] = "translate(\(legendX), \(legendY))"
      // Each entry is as wide as its swatch and an estimate of its 12 px label (there is no text measurement here).
      legend.attributes["font-size"] = "12"
      var entryX = 0.0
      for item in legendValues {
        let group = _RenderNode.element("g")
        group.attributes["transform"] = "translate(\(_chartNumber(entryX)), 0)"
        entryX += 16 + Double(item.0.count) * 7 + 14
        let swatch = _RenderNode.element("rect"); swatch.attributes["x"] = "0"; swatch.attributes["y"] = "-9"; swatch.attributes["width"] = "12"; swatch.attributes["height"] = "12"; swatch.attributes["rx"] = "2"; swatch.styles["fill"] = item.1.cssValue
        let text = svgText(item.0, x: 16, y: 1, anchor: "start")
        group.children = [swatch, text]; legend.children.append(group)
      }
      svg.children.insert(legend, at: 0)
    }
    root.children = [svg]
    return root
  }

  /// Renders marks in order, joining line and area marks of one series into a
  /// single path. `forced` repaints every mark in one color (mask content).
  @MainActor func renderMarks(_ marks: [ChartMark], env: _ChartRenderEnvironment, styleValues: [String: Color], forced: Color?, nextPalette: inout Int, legendValues: inout [(String, Color)]) -> [_RenderNode] {
    // A category the domain does not list has no position: such a mark is left out rather than drawn over the first category.
    let marks = marks.filter { env.xDomain.knows($0.x) && env.xDomain.knows($0.xStart) && env.xDomain.knows($0.xEnd) && env.yDomain.knows($0.y) && env.yDomain.knows($0.yStart) && env.yDomain.knows($0.yEnd) }
    var nodes: [_RenderNode] = []
    var consumedSeries = Set<Int>()
    // Series are grouped once, in first-seen order, rather than filtering every mark for each line or area.
    var seriesGroups: [String: [Int]] = .init()
    for index in marks.indices where marks[index].kind == .line || marks[index].kind == .area {
      seriesGroups[(marks[index].kind == .line ? "line|" : "area|") + seriesKey(marks[index]), default: []].append(index)
    }
    var legendNames = Set(legendValues.map { $0.0 })
    let inMask = forced != nil
    for index in marks.indices {
      if consumedSeries.contains(index) { continue }
      let mark = marks[index]
      let style = forced ?? mark.foregroundStyle ?? color(for: mark, styleValues: styleValues, nextPalette: &nextPalette)
      if !inMask, let by = mark.foregroundStyleValue, legendNames.insert(by.rawValue).inserted { legendValues.append((by.rawValue, style)) }
      let rendered: _RenderNode?
      if mark.kind == .line || mark.kind == .area {
        let key = (mark.kind == .line ? "line|" : "area|") + seriesKey(mark)
        let seriesIndices = seriesGroups[key] ?? [index]
        consumedSeries.formUnion(seriesIndices)
        let series = seriesIndices.map { marks[$0] }
        rendered = mark.kind == .line
          ? renderLineSeries(series, color: style, env: env, inMask: inMask)
          : renderAreaSeries(series, color: style, env: env, inMask: inMask)
      } else {
        consumedSeries.insert(index)
        rendered = render(mark: mark, color: style, env: env, inMask: inMask, key: "mark-\(index)")
      }
      guard let node = rendered else { continue }
      if let maskMarks = mark.maskMarks, !inMask { applyMask(maskMarks, to: node, env: env) }
      nodes.append(node)
    }
    return nodes
  }

  @MainActor private func applyMask(_ maskMarks: [ChartMark], to node: _RenderNode, env: _ChartRenderEnvironment) {
    var palette = 0
    var legend: [(String, Color)] = []
    let content = renderMarks(maskMarks, env: env, styleValues: .init(), forced: .white, nextPalette: &palette, legendValues: &legend)
    // The chart's identity path makes the id unique per chart: two charts with the same marks must not share a mask.
    var signature = "\(env.context._compactPathID)|\(_chartNumber(env.layout.width))x\(_chartNumber(env.layout.height))"
    for mark in maskMarks {
      signature += "|\(_chartMarkKindName(mark.kind))"
      for value in [mark.x, mark.y, mark.xStart, mark.xEnd, mark.yStart, mark.yEnd, mark.seriesValue] { signature += ",\(value?.rawValue ?? "-")" }
    }
    let id = "swc-mask-" + _chartHash(signature)
    let defs = _RenderNode.element("defs")
    let mask = _RenderNode.element("mask")
    mask.attributes["id"] = id
    mask.attributes["maskUnits"] = "userSpaceOnUse"
    mask.attributes["x"] = "0"; mask.attributes["y"] = "0"
    mask.attributes["width"] = _chartNumber(env.layout.width); mask.attributes["height"] = _chartNumber(env.layout.height)
    mask.children = content
    defs.children = [mask]
    node.children.insert(defs, at: 0)
    node.attributes["mask"] = "url(#\(id))"
  }

  private func seriesKey(_ mark: ChartMark) -> String {
    let prefix = mark.seriesValue.map { "series:\($0.rawValue)|" } ?? ""
    if let value = mark.foregroundStyleValue { return prefix + "value:\(value.rawValue)" }
    if let color = mark.foregroundStyle { return prefix + "color:\(color.cssValue)" }
    return prefix + "default:\(_chartMarkKindName(mark.kind))"
  }

  /// The fill or stroke for a mark: an SVG gradient reference when the mark
  /// has a linear gradient style (the definition is appended to `defs`),
  /// otherwise its solid color.
  @MainActor private func paint(for mark: ChartMark, color: Color, env: _ChartRenderEnvironment, userSpace: Bool, defs: inout [_RenderNode]) -> String {
    guard let gradient = mark.foregroundGradient, color.cssValue == (gradient.gradient.stops.first?.color.cssValue ?? "") else { return color.cssValue }
    var css = userSpace ? "user" : "box"
    for stop in gradient.gradient.stops { css += "|\(stop.color.cssValue)@\(_chartNumber(stop.location))" }
    css += "|\(_chartNumber(gradient.startPoint.x)),\(_chartNumber(gradient.startPoint.y))>\(_chartNumber(gradient.endPoint.x)),\(_chartNumber(gradient.endPoint.y))"
    // Keyed by the chart's identity path too, so two charts on one page never share a gradient definition.
    let id = "swc-grad-" + _chartHash(env.context._compactPathID + "|" + css)
    let definition = _RenderNode.element("linearGradient")
    definition.attributes["id"] = id
    if userSpace {
      // Lines are thin or flat, so an object-bounding-box gradient would
      // collapse; span the plot instead.
      definition.attributes["gradientUnits"] = "userSpaceOnUse"
      definition.attributes["x1"] = _chartNumber(env.layout.left + gradient.startPoint.x * env.layout.plotWidth)
      definition.attributes["y1"] = _chartNumber(env.layout.top + gradient.startPoint.y * env.layout.plotHeight)
      definition.attributes["x2"] = _chartNumber(env.layout.left + gradient.endPoint.x * env.layout.plotWidth)
      definition.attributes["y2"] = _chartNumber(env.layout.top + gradient.endPoint.y * env.layout.plotHeight)
    } else {
      definition.attributes["x1"] = "\(_chartNumber(gradient.startPoint.x * 100))%"
      definition.attributes["y1"] = "\(_chartNumber(gradient.startPoint.y * 100))%"
      definition.attributes["x2"] = "\(_chartNumber(gradient.endPoint.x * 100))%"
      definition.attributes["y2"] = "\(_chartNumber(gradient.endPoint.y * 100))%"
    }
    for stop in gradient.gradient.stops {
      let node = _RenderNode.element("stop")
      node.attributes["offset"] = _chartNumber(stop.location)
      node.styles["stop-color"] = stop.color.cssValue
      definition.children.append(node)
    }
    let wrapper = _RenderNode.element("defs")
    wrapper.children = [definition]
    defs.append(wrapper)
    return "url(#\(id))"
  }

  private func symbolShape(for mark: ChartMark, env: _ChartRenderEnvironment) -> BasicChartSymbolShape? {
    if let shape = mark.symbolShape { return shape }
    guard let value = mark.symbolValue, let index = env.symbolOrder.firstIndex(of: value.rawValue) else { return nil }
    return BasicChartSymbolShape.cycle[index % BasicChartSymbolShape.cycle.count]
  }

  private func symbolNode(_ shape: BasicChartSymbolShape, x: Double, y: Double, radius: Double, paint: String, opacity: Double) -> _RenderNode {
    guard let path = _chartSymbolPath(shape, radius: radius) else {
      let circle = _RenderNode.element("circle")
      circle.attributes["cx"] = _chartNumber(x); circle.attributes["cy"] = _chartNumber(y); circle.attributes["r"] = _chartNumber(radius)
      circle.styles["fill"] = paint; circle.attributes["opacity"] = _chartNumber(opacity)
      circle.attributes["data-chart-symbol"] = "circle"
      return circle
    }
    let node = _RenderNode.element("path")
    node.attributes["d"] = path
    node.attributes["transform"] = "translate(\(_chartNumber(x)) \(_chartNumber(y)))"
    if _chartSymbolIsStroked(shape) {
      node.attributes["fill"] = "none"; node.styles["stroke"] = paint; node.attributes["stroke-width"] = "1.5"; node.attributes["stroke-linecap"] = "round"
    } else {
      node.styles["fill"] = paint
    }
    node.attributes["opacity"] = _chartNumber(opacity)
    node.attributes["data-chart-symbol"] = _chartSymbolName(shape)
    return node
  }

  @MainActor private func renderLineSeries(_ marks: [ChartMark], color: Color, env: _ChartRenderEnvironment, inMask: Bool) -> _RenderNode {
    let group = _RenderNode.element("g")
    group.attributes["data-chart-mark"] = "line"
    let first = marks[0]
    let points = marks.compactMap { mark -> (ChartMark, Double, Double)? in
      guard let x = mark.x, let y = mark.y else { return nil }
      return (mark, env.xScale(x), env.yScale(y))
    }
    var defs: [_RenderNode] = []
    let stroke = paint(for: first, color: color, env: env, userSpace: true, defs: &defs)
    group.children.append(contentsOf: defs)
    let path = _RenderNode.element("path")
    if let curve = _ChartCurve.make(points.map { _ChartPoint(x: $0.1, y: $0.2) }, method: first.interpolationMethod) {
      path.attributes["d"] = curve.pathData()
    } else {
      path.attributes["d"] = ""
    }
    path.attributes["fill"] = "none"; path.styles["stroke"] = stroke; path.attributes["stroke-width"] = _chartNumber(first.lineWidth); path.attributes["stroke-linecap"] = "round"; path.attributes["stroke-linejoin"] = "round"
    if first.opacity != 1 { path.attributes["opacity"] = _chartNumber(first.opacity) }
    group.children.append(path)
    // Symbols mark each data point, in a shape per series with `symbol(by:)`.
    if let shape = symbolShape(for: first, env: env) {
      let radius = max(2, _chartSquareRoot(first.symbolSize) / 2)
      for point in points {
        group.children.append(symbolNode(shape, x: point.1, y: point.2, radius: radius, paint: color.cssValue, opacity: first.opacity))
      }
    }
    // Small, transparent circles provide a stable, accessible target for
    // chart selection without splitting the efficient line path.
    if env.selection != nil, let selectionAxis = env.selectionAxis {
      for point in points {
        let hit = _RenderNode.element("circle"); hit.attributes["cx"] = _chartNumber(point.1); hit.attributes["cy"] = _chartNumber(point.2); hit.attributes["r"] = "8"; hit.attributes["fill"] = "transparent"; hit.attributes["tabindex"] = "0"; hit.attributes["role"] = "button"
        attachSelection(hit, mark: point.0, selection: env.selection, axis: selectionAxis); group.children.append(hit)
      }
    }
    return group
  }

  @MainActor private func renderAreaSeries(_ marks: [ChartMark], color: Color, env: _ChartRenderEnvironment, inMask: Bool) -> _RenderNode {
    let group = _RenderNode.element("g")
    group.attributes["data-chart-mark"] = "area"
    let first = marks[0]
    let points = marks.compactMap { mark -> (ChartMark, Double, Double, Double)? in
      guard let x = mark.x else { return nil }
      let topValue = mark.yEnd ?? mark.y ?? mark.yStart
      let bottomValue = mark.yStart ?? mark.y ?? mark.yEnd
      guard let topValue, let bottomValue else { return nil }
      return (mark, env.xScale(x), env.yScale(topValue), env.yScale(bottomValue))
    }
    var defs: [_RenderNode] = []
    let fill = paint(for: first, color: color, env: env, userSpace: false, defs: &defs)
    group.children.append(contentsOf: defs)
    let path = _RenderNode.element("path")
    let top = _ChartCurve.make(points.map { _ChartPoint(x: $0.1, y: $0.2) }, method: first.interpolationMethod)
    let bottom = _ChartCurve.make(points.map { _ChartPoint(x: $0.1, y: $0.3) }, method: first.interpolationMethod)
    if let top, let bottom {
      path.attributes["d"] = top.pathData() + " " + bottom.reversed().pathData(command: "L") + " Z"
    } else {
      path.attributes["d"] = ""
    }
    // Unstyled areas are translucent; a mask or an explicit gradient paints them solid.
    let baseOpacity = (inMask || first.foregroundGradient != nil) ? 1 : 0.35
    path.styles["fill"] = fill; path.attributes["opacity"] = _chartNumber(baseOpacity * first.opacity)
    group.children.append(path)
    if env.selection != nil, let selectionAxis = env.selectionAxis {
      for point in points {
        let hit = _RenderNode.element("rect"); hit.attributes["x"] = _chartNumber(point.1 - 8); hit.attributes["y"] = _chartNumber(min(point.2, point.3)); hit.attributes["width"] = "16"; hit.attributes["height"] = _chartNumber(abs(point.3 - point.2)); hit.attributes["fill"] = "transparent"; attachSelection(hit, mark: point.0, selection: env.selection, axis: selectionAxis); group.children.append(hit)
      }
    }
    return group
  }

  /// Width of one category slot, or nil on a continuous axis.
  private func bandWidth(_ domain: _ChartDomain, extent: Double) -> Double? {
    domain.categoryMode ? extent / Double(max(domain.categories.count, 1)) : nil
  }

  private func length(_ dimension: MarkDimension?, band: Double?, fallback: Double) -> Double {
    guard let dimension else { return fallback }
    let reference = band ?? fallback
    switch dimension.kind {
    case .automatic: return fallback
    case .fixed(let value): return max(0, value)
    case .ratio(let ratio): return max(0, reference * ratio)
    case .inset(let inset): return max(0, reference - 2 * inset)
    }
  }

  /// The pixel box a mark occupies, for bars, rectangles and annotations.
  private func box(for mark: ChartMark, env: _ChartRenderEnvironment) -> _ChartMarkBox? {
    let layout = env.layout
    let xBand = bandWidth(env.xDomain, extent: layout.plotWidth)
    let yBand = bandWidth(env.yDomain, extent: layout.plotHeight)
    switch mark.kind {
    case .bar:
      guard let x = mark.x, let y = mark.y else { return nil }
      let px = env.xScale(x), py = env.yScale(y)
      let baseline = layout.top + layout.plotHeight
      let width = xBand.map { min(max($0 * 0.7, 4), 72) } ?? 28
      return _ChartMarkBox(minX: px - width / 2, minY: min(py, baseline), maxX: px + width / 2, maxY: max(py, baseline))
    case .rectangle:
      var minX = layout.left, maxX = layout.left + layout.plotWidth
      var minY = layout.top, maxY = layout.top + layout.plotHeight
      if let start = mark.xStart, let end = mark.xEnd {
        let a = env.xScale(start), b = env.xScale(end); minX = min(a, b); maxX = max(a, b)
      } else if let x = mark.x {
        let width = length(mark.rectWidth, band: xBand, fallback: xBand.map { $0 * 0.7 } ?? 24)
        let px = env.xScale(x); minX = px - width / 2; maxX = px + width / 2
      }
      if let start = mark.yStart, let end = mark.yEnd {
        let a = env.yScale(start), b = env.yScale(end); minY = min(a, b); maxY = max(a, b)
      } else if let y = mark.y {
        let height = length(mark.rectHeight, band: yBand, fallback: yBand.map { $0 * 0.7 } ?? 24)
        let py = env.yScale(y); minY = py - height / 2; maxY = py + height / 2
      }
      return _ChartMarkBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    case .point:
      guard let x = mark.x, let y = mark.y else { return nil }
      let radius = _chartSquareRoot(mark.symbolSize) / 2
      let px = env.xScale(x), py = env.yScale(y)
      return _ChartMarkBox(minX: px - radius, minY: py - radius, maxX: px + radius, maxY: py + radius)
    case .line:
      guard let x = mark.x, let y = mark.y else { return nil }
      let px = env.xScale(x), py = env.yScale(y)
      return _ChartMarkBox(minX: px, minY: py, maxX: px, maxY: py)
    case .area:
      guard let x = mark.x else { return nil }
      guard let top = mark.yEnd ?? mark.y ?? mark.yStart else { return nil }
      let bottom = mark.yStart ?? mark.y ?? mark.yEnd ?? top
      let px = env.xScale(x), a = env.yScale(top), b = env.yScale(bottom)
      return _ChartMarkBox(minX: px, minY: min(a, b), maxX: px, maxY: max(a, b))
    case .rule:
      if let y = mark.y { let py = env.yScale(y); return _ChartMarkBox(minX: layout.left, minY: py, maxX: layout.left + layout.plotWidth, maxY: py) }
      if let x = mark.x { let px = env.xScale(x); return _ChartMarkBox(minX: px, minY: layout.top, maxX: px, maxY: layout.top + layout.plotHeight) }
      return nil
    }
  }

  @MainActor private func render(mark: ChartMark, color: Color, env: _ChartRenderEnvironment, inMask: Bool, key: String) -> _RenderNode? {
    let group = _RenderNode.element("g")
    group.attributes["data-chart-mark"] = _chartMarkKindName(mark.kind)
    let layout = env.layout
    var defs: [_RenderNode] = []
    let paint = paint(for: mark, color: color, env: env, userSpace: mark.kind == .rule, defs: &defs)
    group.children.append(contentsOf: defs)
    let markBox = box(for: mark, env: env)
    switch mark.kind {
    case .line:
      guard let x = mark.x, let y = mark.y else { return nil }
      let path = _RenderNode.element("path")
      path.attributes["d"] = "M \(_chartNumber(env.xScale(x))) \(_chartNumber(env.yScale(y)))"
      path.attributes["fill"] = "none"; path.styles["stroke"] = paint; path.attributes["stroke-width"] = _chartNumber(mark.lineWidth); path.attributes["stroke-linecap"] = "round"; path.attributes["stroke-linejoin"] = "round"; path.attributes["opacity"] = _chartNumber(mark.opacity)
      attachSelection(path, mark: mark, selection: env.selection, axis: env.selectionAxis)
      group.children.append(path)
    case .bar:
      guard let markBox else { return nil }
      let rect = _RenderNode.element("rect"); rect.attributes["x"] = _chartNumber(markBox.minX); rect.attributes["y"] = _chartNumber(markBox.minY); rect.attributes["width"] = _chartNumber(markBox.maxX - markBox.minX); rect.attributes["height"] = _chartNumber(markBox.maxY - markBox.minY); rect.styles["fill"] = paint; rect.attributes["opacity"] = _chartNumber(mark.opacity); rect.attributes["rx"] = _chartNumber(mark.cornerRadius ?? 2)
      attachSelection(rect, mark: mark, selection: env.selection, axis: env.selectionAxis); group.children.append(rect)
    case .rectangle:
      guard let markBox else { return nil }
      let rect = _RenderNode.element("rect"); rect.attributes["x"] = _chartNumber(markBox.minX); rect.attributes["y"] = _chartNumber(markBox.minY); rect.attributes["width"] = _chartNumber(markBox.maxX - markBox.minX); rect.attributes["height"] = _chartNumber(markBox.maxY - markBox.minY); rect.styles["fill"] = paint; rect.attributes["opacity"] = _chartNumber(mark.opacity)
      if let radius = mark.cornerRadius, radius > 0 { rect.attributes["rx"] = _chartNumber(radius) }
      attachSelection(rect, mark: mark, selection: env.selection, axis: env.selectionAxis); group.children.append(rect)
    case .area:
      guard let x = mark.x else { return nil }
      let topValue = mark.yEnd ?? mark.y ?? mark.yStart; let bottomValue = mark.yStart ?? mark.y ?? mark.yEnd
      guard let topValue, let bottomValue else { return nil }
      let px = env.xScale(x); let top = env.yScale(topValue); let bottom = env.yScale(bottomValue)
      let path = _RenderNode.element("path"); path.attributes["d"] = "M \(_chartNumber(px)) \(_chartNumber(bottom)) L \(_chartNumber(px)) \(_chartNumber(top)) L \(_chartNumber(px + 1)) \(_chartNumber(top)) L \(_chartNumber(px + 1)) \(_chartNumber(bottom)) Z"; path.styles["fill"] = paint; path.attributes["opacity"] = _chartNumber(mark.opacity * 0.35); attachSelection(path, mark: mark, selection: env.selection, axis: env.selectionAxis); group.children.append(path)
    case .point:
      guard let x = mark.x, let y = mark.y else { return nil }
      let radius = _chartSquareRoot(mark.symbolSize) / 2
      let node = symbolNode(symbolShape(for: mark, env: env) ?? .circle, x: env.xScale(x), y: env.yScale(y), radius: radius, paint: paint, opacity: mark.opacity)
      attachSelection(node, mark: mark, selection: env.selection, axis: env.selectionAxis); group.children.append(node)
    case .rule:
      let line = _RenderNode.element("line"); line.styles["stroke"] = paint; line.attributes["stroke-width"] = _chartNumber(mark.lineWidth); line.attributes["opacity"] = _chartNumber(mark.opacity)
      if let y = mark.y { line.attributes["x1"] = _chartNumber(layout.left); line.attributes["x2"] = _chartNumber(layout.left + layout.plotWidth); line.attributes["y1"] = _chartNumber(env.yScale(y)); line.attributes["y2"] = _chartNumber(env.yScale(y)); attachSelection(line, mark: mark, selection: env.selection, axis: env.selectionAxis) }
      else if let x = mark.x { line.attributes["x1"] = _chartNumber(env.xScale(x)); line.attributes["x2"] = _chartNumber(env.xScale(x)); line.attributes["y1"] = _chartNumber(layout.top); line.attributes["y2"] = _chartNumber(layout.top + layout.plotHeight); attachSelection(line, mark: mark, selection: env.selection, axis: env.selectionAxis) }
      group.children.append(line)
    }
    if !inMask, let annotation = mark.annotation, let position = mark.annotationPosition, let markBox {
      group.children.append(annotationNode(annotation, position: position, spacing: mark.annotationSpacing, box: markBox, env: env, key: key))
    }
    return group
  }

  /// An annotation is an arbitrary view, realized in an SVG `foreignObject`
  /// next to the mark. Its box is fixed; the view is centered against the
  /// mark's edge inside it.
  @MainActor private func annotationNode(_ view: AnyView, position: ChartAnnotationPosition, spacing: Double?, box: _ChartMarkBox, env: _ChartRenderEnvironment, key: String) -> _RenderNode {
    let width = 160.0, height = 56.0
    let gap = spacing ?? 4
    let x: Double, y: Double
    var justify = "center", align = "center"
    switch position {
    case .top: x = box.centerX - width / 2; y = box.minY - gap - height; align = "flex-end"
    case .bottom: x = box.centerX - width / 2; y = box.maxY + gap; align = "flex-start"
    case .leading: x = box.minX - gap - width; y = box.centerY - height / 2; justify = "flex-end"
    case .trailing: x = box.maxX + gap; y = box.centerY - height / 2; justify = "flex-start"
    case .overlay: x = box.centerX - width / 2; y = box.centerY - height / 2
    }
    return foreignView(view, x: x, y: y, width: width, height: height, justify: justify, align: align, env: env, key: "annotation-" + key, role: "annotation")
  }

  @MainActor func foreignView(_ view: AnyView, x: Double, y: Double, width: Double, height: Double, justify: String, align: String, env: _ChartRenderEnvironment, key: String, role: String) -> _RenderNode {
    let foreign = _RenderNode.element("foreignObject")
    foreign.attributes["x"] = _chartNumber(x); foreign.attributes["y"] = _chartNumber(y)
    foreign.attributes["width"] = _chartNumber(width); foreign.attributes["height"] = _chartNumber(height)
    foreign.attributes["data-chart-\(role)"] = "true"
    foreign.styles["overflow"] = "visible"
    let box = _RenderNode.element("div")
    box.styles["display"] = "flex"; box.styles["justify-content"] = justify; box.styles["align-items"] = align
    box.styles["width"] = "100%"; box.styles["height"] = "100%"
    box.styles["font-size"] = "11px"; box.styles["color"] = "currentColor"
    box.children = [view._render(in: env.context.child(_FiberKey(key)))]
    foreign.children = [box]
    return foreign
  }

  private func attachSelection(_ node: _RenderNode, mark: ChartMark, selection: ((ChartValue) -> Void)?, axis: ChartSelectionAxis?) {
    guard let selection, let axis else { return }
    let selected = axis == .x ? mark.x : mark.y
    guard let selected else { return }
    node.events["click"] = _EventHandler(name: "click", action: { selection(selected) })
    node.attributes["tabindex"] = "0"
    node.attributes["role"] = "button"
    node.attributes["aria-label"] = "\(selected.label): \(selected.rawValue)"
  }

  // MARK: Axes

  struct _AxisEntry {
    let value: ChartValue
    let items: [_AxisItem]
  }

  struct _ResolvedAxis {
    var entries: [_AxisEntry]
    var hasViewLabels: Bool
  }

  /// The values each `AxisMarks` shows and the marks it draws for each.
  @MainActor func resolveAxis(_ marks: [AxisMarks], domain: _ChartDomain) -> _ResolvedAxis {
    var entries: [_AxisEntry] = []
    var hasViewLabels = false
    for group in marks {
      let values = tickValues(group, domain: domain)
      for (index, value) in values.enumerated() {
        let items = group.items(for: AxisValue(index: index, count: values.count, chartValue: value))
        if items.contains(where: { $0.view != nil }) { hasViewLabels = true }
        entries.append(_AxisEntry(value: value, items: items))
      }
    }
    return _ResolvedAxis(entries: entries, hasViewLabels: hasViewLabels)
  }

  private func tickValues(_ marks: AxisMarks, domain: _ChartDomain) -> [ChartValue] {
    if let explicit = marks.explicitValues { return explicit }
    if domain.categoryMode { return domain.categories.map { ChartValue.value("", $0) } }
    return _chartAxisValues(marks.valueSpec, lower: domain.lower, upper: domain.upper, isDate: domain.isDate).map { number in
      domain.isDate ? ChartValue.value("", Date(timeIntervalSince1970: number)) : ChartValue.value("", number)
    }
  }

  private func labelText(_ item: _AxisItem, value: ChartValue, domain: _ChartDomain) -> String {
    if let text = item.text { return text }
    guard let number = value.numericValue else { return value.rawValue }
    if let format = item.format { return format(number) }
    if domain.isDate || value._isDate { return _chartDefaultDateLabel(number, range: domain.upper - domain.lower) }
    return _chartNumber(number)
  }

  private func strokeLine(_ line: _RenderNode, stroke: StrokeStyle?, opacity: String) {
    line.attributes["stroke"] = "currentColor"
    line.attributes["stroke-opacity"] = opacity
    guard let stroke else { return }
    line.attributes["stroke-width"] = _chartNumber(stroke.lineWidth)
    if !stroke.dash.isEmpty { line.attributes["stroke-dasharray"] = stroke.dash.map { _chartNumber($0) }.joined(separator: " ") }
  }

  @MainActor private func customAxisNodes(_ axis: _ResolvedAxis, isX: Bool, env: _ChartRenderEnvironment) -> [_RenderNode] {
    let layout = env.layout
    let domain = isX ? env.xDomain : env.yDomain
    let bottomEdge = layout.top + layout.plotHeight
    var nodes: [_RenderNode] = []
    for (entryIndex, entry) in axis.entries.enumerated() {
      let position = isX ? env.xScale(entry.value) : env.yScale(entry.value)
      let hasTick = entry.items.contains { $0.kind == .tick }
      for item in entry.items {
        switch item.kind {
        case .gridLine:
          let line = _RenderNode.element("line")
          if isX { line.attributes["x1"] = _chartNumber(position); line.attributes["x2"] = _chartNumber(position); line.attributes["y1"] = _chartNumber(layout.top); line.attributes["y2"] = _chartNumber(bottomEdge) }
          else { line.attributes["x1"] = _chartNumber(layout.left); line.attributes["x2"] = _chartNumber(layout.left + layout.plotWidth); line.attributes["y1"] = _chartNumber(position); line.attributes["y2"] = _chartNumber(position) }
          strokeLine(line, stroke: item.stroke, opacity: "0.12")
          line.attributes["data-chart-axis-grid"] = isX ? "x" : "y"
          nodes.append(line)
        case .tick:
          let length = item.tickLength ?? 5
          let line = _RenderNode.element("line")
          if isX { line.attributes["x1"] = _chartNumber(position); line.attributes["x2"] = _chartNumber(position); line.attributes["y1"] = _chartNumber(bottomEdge); line.attributes["y2"] = _chartNumber(bottomEdge + length) }
          else {
            let edge = layout.yAxisLeading ? layout.left : layout.left + layout.plotWidth
            line.attributes["x1"] = _chartNumber(edge); line.attributes["x2"] = _chartNumber(layout.yAxisLeading ? edge - length : edge + length)
            line.attributes["y1"] = _chartNumber(position); line.attributes["y2"] = _chartNumber(position)
          }
          strokeLine(line, stroke: item.stroke, opacity: "0.35")
          line.attributes["data-chart-axis-tick"] = isX ? "x" : "y"
          nodes.append(line)
        case .label:
          let pad = hasTick ? 8.0 : 4.0
          if let view = item.view {
            if isX {
              let width = domainBand(domain, extent: layout.plotWidth) ?? 80
              nodes.append(foreignView(view, x: position - width / 2, y: bottomEdge + pad, width: width, height: layout.bottom - pad - 4, justify: "center", align: "flex-start", env: env, key: "axis-x-\(entryIndex)", role: "axis-label"))
            } else {
              let x = layout.yAxisLeading ? layout.left - pad - 64 : layout.left + layout.plotWidth + pad
              nodes.append(foreignView(view, x: x, y: position - 12, width: 64, height: 24, justify: layout.yAxisLeading ? "flex-end" : "flex-start", align: "center", env: env, key: "axis-y-\(entryIndex)", role: "axis-label"))
            }
          } else {
            let text = labelText(item, value: entry.value, domain: domain)
            let label = isX ? svgText(text, x: position, y: bottomEdge + 12 + pad, anchor: "middle")
              : layout.yAxisLeading ? svgText(text, x: layout.left - pad - 2, y: position + 4, anchor: "end")
              : svgText(text, x: layout.left + layout.plotWidth + pad + 2, y: position + 4, anchor: "start")
            label.attributes["fill"] = "currentColor"; label.attributes["font-size"] = "11"
            label.attributes["data-chart-axis-label"] = isX ? "x" : "y"
            nodes.append(label)
          }
        }
      }
    }
    return nodes
  }

  private func domainBand(_ domain: _ChartDomain, extent: Double) -> Double? { bandWidth(domain, extent: extent) }

  @MainActor private func axes(env: _ChartRenderEnvironment, config: _ChartConfiguration, xAxis: _ResolvedAxis?, yAxis: _ResolvedAxis?) -> [_RenderNode] {
    let layout = env.layout
    let xDomain = env.xDomain, yDomain = env.yDomain
    var nodes: [_RenderNode] = []
    if config.yAxis.visibility != .hidden {
      if let yAxis {
        nodes.append(contentsOf: customAxisNodes(yAxis, isX: false, env: env))
      } else {
        let yValues = config.yAxis.values ?? (0..<5).map { index in yDomain.lower + (yDomain.upper - yDomain.lower) * Double(index) / 4 }
        for value in yValues {
          let fraction = (value - yDomain.lower) / max(yDomain.upper - yDomain.lower, 0.000001); let y = layout.top + layout.plotHeight - (yDomain.reversed ? 1 - fraction : fraction) * layout.plotHeight
          let grid = _RenderNode.element("line"); grid.attributes["x1"] = _chartNumber(layout.left); grid.attributes["x2"] = _chartNumber(layout.left + layout.plotWidth); grid.attributes["y1"] = _chartNumber(y); grid.attributes["y2"] = _chartNumber(y); grid.attributes["stroke"] = "currentColor"; grid.attributes["stroke-opacity"] = "0.12"; nodes.append(grid)
          let label = layout.yAxisLeading
            ? svgText(_chartNumber(value), x: layout.left - 8, y: y + 4, anchor: "end")
            : svgText(_chartNumber(value), x: layout.left + layout.plotWidth + 8, y: y + 4, anchor: "start")
          label.attributes["fill"] = "currentColor"; label.attributes["font-size"] = "11"; nodes.append(label)
        }
      }
    }
    if config.xAxis.visibility != .hidden {
      let base = _RenderNode.element("line"); base.attributes["x1"] = _chartNumber(layout.left); base.attributes["x2"] = _chartNumber(layout.left + layout.plotWidth); base.attributes["y1"] = _chartNumber(layout.top + layout.plotHeight); base.attributes["y2"] = _chartNumber(layout.top + layout.plotHeight); base.attributes["stroke"] = "currentColor"; base.attributes["stroke-opacity"] = "0.35"; nodes.append(base)
      if let xAxis {
        nodes.append(contentsOf: customAxisNodes(xAxis, isX: true, env: env))
      } else {
        // Keep the two tuple-producing branches explicit. Apart from making the
        // intent clearer, this avoids a Swift type-checker blow-up in release
        // builds when the chart target is present only as an optional product.
        let values: [(Double, String)]
        if xDomain.categoryMode {
          values = xDomain.categories.enumerated().map { (Double($0.offset), $0.element) }
        } else {
          let numericValues = config.xAxis.values ?? (0..<5).map { index in
            xDomain.lower + (xDomain.upper - xDomain.lower) * Double(index) / 4
          }
          values = numericValues.map { ($0, xDomain.isDate ? _chartDefaultDateLabel($0, range: xDomain.upper - xDomain.lower) : _chartNumber($0)) }
        }
        for (raw, labelValue) in values { let fraction = ((raw - xDomain.lower) / max(xDomain.upper - xDomain.lower, 0.000001)); let x = layout.left + (xDomain.reversed ? 1 - fraction : fraction) * layout.plotWidth; let label = svgText(labelValue, x: x, y: layout.top + layout.plotHeight + 18, anchor: "middle"); label.attributes["fill"] = "currentColor"; label.attributes["font-size"] = "11"; nodes.append(label) }
      }
    }
    if let label = config.xAxisLabel { nodes.append(svgText(label, x: layout.left + layout.plotWidth / 2, y: layout.height - 4, anchor: "middle")) }
    if let label = config.yAxisLabel { let node = svgText(label, x: 12, y: layout.top + layout.plotHeight / 2, anchor: "middle"); node.attributes["transform"] = "rotate(-90 12 \(layout.top + layout.plotHeight / 2))"; nodes.append(node) }
    return nodes
  }

  private func domain(for marks: [ChartMark], axis: ChartSelectionAxis, explicit: ChartScaleDomain?, automatic: AutomaticScaleDomain?) -> _ChartDomain {
    let reversed = automatic?.reversed ?? false
    if let explicit {
      var isDate = explicit.lowerBound._isDate
      if let lo = explicit.lowerBound.numericValue, let hi = explicit.upperBound.numericValue { isDate = isDate || explicit.upperBound._isDate; return _ChartDomain(lower: lo, upper: hi == lo ? lo + 1 : hi, categories: [], categoryMode: false, label: explicit.lowerBound.label, isDate: isDate, reversed: reversed) }
      return _ChartDomain(lower: 0, upper: 1, categories: [explicit.lowerBound.rawValue, explicit.upperBound.rawValue], categoryMode: true, label: explicit.lowerBound.label, reversed: reversed)
    }
    var values: [ChartValue] = []
    for mark in marks {
      if axis == .x { for value in [mark.x, mark.xStart, mark.xEnd] { if let value { values.append(value) } } }
      else { for value in [mark.y, mark.yStart, mark.yEnd] { if let value { values.append(value) } } }
    }
    let label = values.first?.label ?? ""
    if values.contains(where: { $0.numericValue == nil }) {
      var categories: [String] = []
      var seenCategories = Set<String>()
      for value in values where seenCategories.insert(value.rawValue).inserted { categories.append(value.rawValue) }
      // Give categorical bars/points half a band of breathing room at each
      // edge, matching the default band scale used by Swift Charts.
      return _ChartDomain(lower: -0.5, upper: max(0.5, Double(categories.count) - 0.5), categories: categories, categoryMode: true, label: label, reversed: reversed)
    }
    let nums = values.compactMap { value in value.numericValue }; let minValue = nums.min() ?? 0; let maxValue = nums.max() ?? 1; let padding = max((maxValue - minValue) * 0.08, 1)
    // Bars grow from zero, so a y axis carrying bars includes it by default.
    let includesZero = automatic?.includesZero ?? (axis == .y && marks.contains(where: { $0.kind == .bar }))
    var lower = minValue - padding
    var upper = maxValue + padding
    if includesZero { lower = min(lower, 0); upper = max(upper, 0); if minValue >= 0 { lower = 0 } }
    return _ChartDomain(lower: lower, upper: upper, categories: [], categoryMode: false, label: label, isDate: values.contains(where: { $0._isDate }), reversed: reversed)
  }

  private func color(for mark: ChartMark, styleValues: [String: Color], nextPalette: inout Int) -> Color {
    if let value = mark.foregroundStyleValue {
      if let explicit = styleValues[value.rawValue] { return explicit }
      let color = palette[nextPalette % palette.count]; nextPalette += 1; return color
    }
    // Unstyled marks belong to the default series; keeping one stable color
    // avoids rainbow point clouds for large data sets.
    return palette[0]
  }

  func svgText(_ text: String, x: Double, y: Double, anchor: String) -> _RenderNode {
    let node = _RenderNode.element("text"); node.attributes["x"] = _chartNumber(x); node.attributes["y"] = _chartNumber(y); node.attributes["text-anchor"] = anchor; node.children = [.text(text)]; return node
  }
  private func chartLabel(_ marks: [ChartMark]) -> String {
    if let label = marks.first?.x?.label, !label.isEmpty { return "Chart of \(label)" }
    return "Chart"
  }
}

func _chartMarkKindName(_ kind: ChartMark.Kind) -> String {
  switch kind {
  case .line: return "line"
  case .bar: return "bar"
  case .area: return "area"
  case .point: return "point"
  case .rule: return "rule"
  case .rectangle: return "rectangle"
  }
}

func _chartSymbolName(_ shape: BasicChartSymbolShape) -> String {
  switch shape.kind {
  case .circle: return "circle"
  case .square: return "square"
  case .triangle: return "triangle"
  case .diamond: return "diamond"
  case .pentagon: return "pentagon"
  case .plus: return "plus"
  case .cross: return "cross"
  case .asterisk: return "asterisk"
  }
}

/// FNV-1a, as hex: a stable id for gradient and mask definitions. Equal
/// content hashes equally, so repeated definitions are harmless duplicates.
func _chartHash(_ text: String) -> String {
  var hash: UInt32 = 2_166_136_261
  for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
  let digits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
  var result = ""
  var shift: UInt32 = 28
  while true {
    result.append(digits[Int((hash >> shift) & 0xF)])
    if shift == 0 { break }
    shift -= 4
  }
  return result
}

private func _chartValue<V: Comparable>(_ value: V) -> ChartValue {
  if let value = value as? Double { return .value("", value) }
  if let value = value as? Float { return .value("", value) }
  if let value = value as? Int { return .value("", value) }
  if let value = value as? Int8 { return .value("", value) }
  if let value = value as? Int16 { return .value("", value) }
  if let value = value as? Int32 { return .value("", value) }
  if let value = value as? Int64 { return .value("", value) }
  if let value = value as? UInt { return .value("", value) }
  if let value = value as? UInt8 { return .value("", value) }
  if let value = value as? UInt16 { return .value("", value) }
  if let value = value as? UInt32 { return .value("", value) }
  if let value = value as? UInt64 { return .value("", value) }
  if let value = value as? String { return .value("", value) }
  if let value = value as? Date { return .value("", value) }
#if hasFeature(Embedded)
  // Embedded Swift 6.4 exposes the Hashable/Comparable constraints but not
  // their runtime hashing entry points. Primitive/date/string categories are
  // handled above; keep the erased fallback runtime-free.
  return .value("", "value")
#else
  return .value("", String(describing: value))
#endif
}

private func _decodeChartValue<V: Hashable>(_ value: ChartValue) -> V? {
  if V.self == Double.self, let number = value.numericValue { return number as? V }
  if V.self == Float.self, let number = value.numericValue { return Float(number) as? V }
  // A value Int cannot hold (past 2^31 in the browser build, where Int is 32 bits) selects nothing instead of trapping.
  if V.self == Int.self, let number = value.numericValue, number.isFinite { return Int(exactly: number.rounded(.towardZero)) as? V }
  if V.self == String.self { return value.rawValue as? V }
  if V.self == Date.self, let number = value.numericValue { return Date(timeIntervalSince1970: number) as? V }
  return nil
}

func _chartNumber(_ value: Double) -> String {
  guard value.isFinite else { return "0" }
  // Int64(exactly:) is nil, not a trap, for a whole value Int64 cannot hold (a remote value of 1e300).
  if let whole = Int64(exactly: value) { return String(whole) }
  // Past 1e15 a Double has no fraction left to round, and `value * 1000` below could overflow to infinity.
  if value.magnitude >= 1e15 { return String(value) }
  let scaled = (value * 1000).rounded() / 1000
  var text = String(scaled)
  // Swift writes a magnitude past Int64 as 1e+30: its exponent is not a fraction to trim.
  if text.contains("e") { return text }
  while text.last == "0" { text.removeLast() }
  if text.last == "." { text.removeLast() }
  return text
}

// Foundation-free Newton iteration keeps the chart target buildable on WASI.
private func _chartSquareRoot(_ value: Double) -> Double {
  guard value > 0 else { return 0 }
  var estimate = value > 1 ? value : 1
  for _ in 0..<8 { estimate = (estimate + value / estimate) / 2 }
  return estimate
}

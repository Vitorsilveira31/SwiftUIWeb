import Foundation
import Testing
import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebCharts
import SwiftUIWebHTML

/// The call shapes of Apple's Food Truck sample, rendered for real.
@Suite
@MainActor
final class ChartAxisAndMarkTests {
  private struct Sale: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
  }

  private struct Reading: Identifiable {
    let hour: Int
    let degrees: Double
    var date: Date { Date(timeIntervalSince1970: Double(hour) * 3_600) }
    var id: Int { hour }
  }

  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }

  @Test
  func testBarChartWithCustomAxesGradientAndViewLabels() {
    let sales = [Sale(name: "Glazed", count: 12), Sale(name: "Cake", count: 30)]
    let chart = Chart {
      ForEach(sales) { sale in
        BarMark(x: .value("Donut", sale.name), y: .value("Sales", sale.count))
          .cornerRadius(6, style: .continuous)
          .foregroundStyle(.linearGradient(colors: [.red, .blue], startPoint: .bottom, endPoint: .top))
          .annotation(position: .top, alignment: .top) { Text("annotated \(sale.count)") }
      }
    }
    .chartYAxis {
      AxisMarks { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: IntegerFormatStyle<Int>())
      }
    }
    .chartXAxis {
      AxisMarks { value in
        AxisValueLabel {
          let name = value.as(String.self) ?? "?"
          VStack { Text("label-" + name) }
        }
      }
    }
    let output = html(chart)
    _expectTrue(output.contains("<linearGradient"), "A gradient foreground style becomes an SVG gradient")
    _expectTrue(output.contains("url(#swc-grad-"))
    _expectTrue(output.contains("rx=\"6\""), "cornerRadius reaches the bar")
    _expectTrue(output.contains("data-chart-axis-grid=\"y\""))
    _expectTrue(output.contains("data-chart-axis-tick=\"y\""))
    _expectTrue(output.contains("data-chart-axis-label=\"y\""))
    _expectTrue(output.contains("label-Glazed") && output.contains("label-Cake"), "View labels render per category")
    _expectTrue(output.contains("<foreignObject"))
    _expectTrue(output.contains("annotated 30"))
  }

  @Test
  func testAxisValueExposesIndexCountAndTypedValue() {
    var seen: [String] = []
    let chart = Chart {
      PointMark(x: .value("X", 1), y: .value("Y", 1))
      PointMark(x: .value("X", 9), y: .value("Y", 9))
    }
    .chartXAxis {
      AxisMarks(values: [2, 4, 6]) { value in
        AxisValueLabel("\(value.index)/\(value.count)=\(value.as(Double.self)!.formatted())")
      }
    }
    .chartYAxis {
      AxisMarks(values: ["a"]) { value in
        AxisValueLabel("\(value.as(String.self) ?? "nil")")
      }
    }
    let output = html(chart)
    seen.append(output)
    _expectTrue(output.contains("0/3=2") && output.contains("1/3=4") && output.contains("2/3=6"))
    _expectTrue(output.contains(">a<"))
  }

  @Test
  func testStrideAndAutomaticMarkValuesPlaceLabels() {
    func labels(_ values: AxisMarkValues) -> [String] {
      let chart = Chart {
        LineMark(x: .value("X", 0), y: .value("Y", 0))
        LineMark(x: .value("X", 20), y: .value("Y", 40))
      }
      .chartYAxis {
        AxisMarks(values: values) { _ in AxisValueLabel() }
      }
      let node = chart._render(in: _RenderContext())
      var found: [String] = []
      func walk(_ node: _RenderNode) {
        if node.attributes["data-chart-axis-label"] == "y" { found.append(node.children.first?.text ?? "") }
        node.children.forEach(walk)
      }
      walk(node)
      return found
    }
    let stride = labels(.stride(by: 10))
    _expectTrue(stride.contains("10") && stride.contains("30"), "stride(by: 10) marks multiples of ten: \(stride)")
    let minimum = labels(.automatic(minimumStride: 25, desiredCount: 8))
    _expectTrue(minimum.count <= 3, "minimumStride bounds how dense marks get: \(minimum)")
    let desired = labels(.automatic(desiredCount: 3))
    _expectTrue(desired.count >= 2 && desired.count <= 6, "\(desired)")
  }

  @Test
  func testDateBinsAndDateAxisFormatting() {
    let start = Date(timeIntervalSince1970: 0)
    let bins = DateBins(unit: .hour, by: 3, range: start...start.addingTimeInterval(24 * 3_600))
    _expectEqual(bins.thresholds.count, 9)
    let readings = (0...24).map { Reading(hour: $0, degrees: 60 + Double($0 % 7)) }
    let chart = Chart {
      ForEach(readings) { reading in
        LineMark(x: .value("Hour", reading.date), y: .value("Temp", reading.degrees))
      }
    }
    .chartXAxis {
      AxisMarks(values: bins.thresholds) { _ in
        AxisValueLabel(format: .dateTime.hour())
        AxisTick()
        AxisGridLine()
      }
    }
    let node = chart._render(in: _RenderContext())
    var labels = 0
    var ticks = 0
    func walk(_ node: _RenderNode) {
      if node.attributes["data-chart-axis-label"] == "x" { labels += 1 }
      if node.attributes["data-chart-axis-tick"] == "x" { ticks += 1 }
      node.children.forEach(walk)
    }
    walk(node)
    _expectEqual(labels, 9)
    _expectEqual(ticks, 9)
  }

  @Test
  func testAreaWithSeriesRectangleMaskAndAutomaticDomain() {
    let readings = (0...6).map { Reading(hour: $0, degrees: 60 + Double($0) * 2) }
    let chart = Chart {
      ForEach(readings) { reading in
        AreaMark(
          x: .value("Hour", reading.date),
          yStart: .value("Temperature", 58),
          yEnd: .value("Temperature", reading.degrees),
          series: .value("Temperature", 0)
        )
        .interpolationMethod(.catmullRom)
        .foregroundStyle(.linearGradient(colors: [.teal, .yellow], startPoint: .bottom, endPoint: .top))
      }
      RectangleMark(
        xStart: .value("Hour", readings[1].date),
        xEnd: .value("Hour", readings[3].date)
      )
      .opacity(0.5)
      .mask {
        ForEach(readings) { reading in
          AreaMark(
            x: .value("Hour", reading.date),
            yStart: .value("Temperature", 58),
            yEnd: .value("Temperature", reading.degrees),
            series: .value("Mask", 1)
          )
        }
      }
      RectangleMark(
        x: .value("Date", readings[2].date),
        yStart: .value("Temperature", 58),
        yEnd: .value("Temperature", 66),
        width: .fixed(4)
      )
      .cornerRadius(2)
    }
    .chartYScale(domain: .automatic(includesZero: false))
    .chartYAxis {
      AxisMarks(values: .automatic(minimumStride: 5, desiredCount: 6, roundLowerBound: false)) { value in
        AxisValueLabel("\(value.as(Double.self)!.formatted())°F")
        AxisTick()
        AxisGridLine()
      }
    }
    let output = html(chart)
    _expectTrue(output.contains(" C "), "catmullRom produces cubic segments")
    _expectTrue(output.contains("<mask"), "mask content becomes an SVG mask")
    _expectTrue(output.contains("mask=\"url(#swc-mask-"))
    _expectTrue(output.contains("°F"))
    _expectTrue(output.contains("width=\"4\""), "A fixed-width RectangleMark is 4 wide")
    _expectTrue(output.contains("data-chart-mark=\"rectangle\""))
    // includesZero: false keeps the y labels near the data rather than at 0.
    _expectFalse(output.contains(">0°F<"))
  }

  @Test
  func testInterpolationSymbolsAndLineStyleOnForEach() {
    struct CitySales: Identifiable { let name: String; let values: [Int]; var id: String { name } }
    let cities = [CitySales(name: "SF", values: [3, 5, 4]), CitySales(name: "NY", values: [2, 6, 1])]
    func chart(_ method: ChartInterpolationMethod) -> String {
      html(Chart {
        ForEach(cities) { city in
          ForEach(Array(city.values.enumerated()), id: \.offset) { entry in
            LineMark(x: .value("Day", entry.offset), y: .value("Sales", entry.element))
              .foregroundStyle(by: .value("Location", city.name))
              .interpolationMethod(method)
              .symbol(by: .value("Location", city.name))
              .opacity(0.8)
          }
          .lineStyle(StrokeStyle(lineWidth: 3))
        }
      }
      .chartLegend(position: .top))
    }
    let cardinal = chart(.cardinal)
    _expectTrue(cardinal.contains(" C "))
    _expectTrue(cardinal.contains("stroke-width=\"3\""), "lineStyle on a ForEach reaches the lines")
    _expectTrue(cardinal.contains("data-chart-symbol=\"circle\""))
    _expectTrue(cardinal.contains("data-chart-symbol=\"square\""), "symbol(by:) assigns one shape per series")
    _expectFalse(chart(.linear).contains(" C "))
    _expectTrue(chart(.monotone).contains(" C "))
    _expectTrue(chart(.catmullRom(alpha: 1)).contains(" C "))
    _expectTrue(chart(.cardinal(tension: 0.5)).contains(" C "))
    let step = chart(.stepEnd)
    _expectFalse(step.contains(" C "))
    _expectTrue(step.contains(" L "))
  }

  @Test
  func testPlotStyleWrapsTheChartForAnyContainingView() {
    struct Wrapper: View {
      var body: some View {
        Chart { PointMark(x: .value("X", 1), y: .value("Y", 2)) }
          .chartLegend(position: .top)
      }
    }
    let styled = Wrapper().chartPlotStyle { content in
      content.chartOverlay { _ in Text("overlay-text") }
    }
    let output = html(styled)
    _expectTrue(output.contains("overlay-text"))
    _expectTrue(output.contains("<svg"), "The chart itself is still rendered inside the styled plot")
    let plain = html(Chart { PointMark(x: .value("X", 1), y: .value("Y", 2)) })
    _expectFalse(plain.contains("overlay-text"))
  }

  @Test
  func testReversedAndNonZeroDomains() {
    func firstBarTop(_ domain: AutomaticScaleDomain) -> String? {
      let chart = Chart {
        BarMark(x: .value("A", "a"), y: .value("V", 100))
        BarMark(x: .value("A", "b"), y: .value("V", 120))
      }
      .chartYScale(domain: domain)
      let node = chart._render(in: _RenderContext())
      var y: String?
      func walk(_ node: _RenderNode) {
        if y == nil, node.attributes["data-chart-mark"] == "bar" { y = node.children.first?.attributes["y"] }
        node.children.forEach(walk)
      }
      walk(node)
      return y
    }
    let zeroBased = firstBarTop(.automatic(includesZero: true))
    let tight = firstBarTop(.automatic(includesZero: false))
    _expectNotNil(zeroBased)
    _expectNotNil(tight)
    _expectTrue(Double(zeroBased ?? "0")! < Double(tight ?? "0")!, "A zero-based scale puts the 100 bar higher than a tight one")
    _expectNotNil(firstBarTop(.automatic(reversed: true)))
  }

  // Exactly the shapes of the Food Truck weather card: multi-statement
  // ForEach closures with `if`, `id: \.lowerBound` over ranges, helper
  // functions returning `some ChartContent`, and modifiers on a ForEach.
  @ChartContentBuilder
  private static func areaMarks(_ readings: [Reading], seriesKey: String, value: Double) -> some ChartContent {
    ForEach(readings) { entry in
      AreaMark(
        x: .value("Hour", entry.date),
        yStart: .value("Temperature", 50),
        yEnd: .value("Temperature", entry.degrees),
        series: .value(seriesKey, value)
      )
      .interpolationMethod(.catmullRom)
    }
  }

  @Test
  func testWeatherCardShapesWithRangesConditionalsAndHelpers() {
    let readings = (0...8).map { Reading(hour: $0, degrees: 60 + Double($0)) }
    let ranges: [Range<Date>] = [readings[1].date..<readings[3].date, readings[5].date..<readings[7].date]
    let chart = Chart {
      Self.areaMarks(readings, seriesKey: "Temperature", value: 0)
        .foregroundStyle(.linearGradient(colors: [.teal, .yellow], startPoint: .bottom, endPoint: .top))

      ForEach(ranges, id: \.lowerBound) { range in
        RectangleMark(
          xStart: .value("Hour", range.lowerBound),
          xEnd: .value("Hour", range.upperBound)
        )
        .opacity(0.5)
        .mask {
          Self.areaMarks(readings, seriesKey: "Mask", value: range.lowerBound.timeIntervalSince1970)
        }

        if range.lowerBound != readings.first!.date {
          let date = range.lowerBound
          RectangleMark(
            x: .value("Date", date),
            yStart: .value("Temperature", 50),
            yEnd: .value("Temperature", 66),
            width: .fixed(4)
          )
          .foregroundStyle(.indigo)
          .cornerRadius(2)
          .annotation(position: .top, alignment: .bottom, spacing: 5) {
            Image(systemName: "moon.circle.fill").imageScale(.large)
          }
        }
      }
    }
    .chartXAxis {
      AxisMarks(values: DateBins(unit: .hour, by: 3, range: readings[0].date...readings[8].date).thresholds) { _ in
        AxisValueLabel(format: .dateTime.hour())
        AxisTick()
        AxisGridLine()
      }
    }
    .chartYScale(domain: .automatic(includesZero: false))
    .chartYAxis {
      AxisMarks(values: .automatic(minimumStride: 5, desiredCount: 6, roundLowerBound: false)) { value in
        AxisValueLabel("\(value.as(Double.self)!.formatted())°F")
        AxisTick()
        AxisGridLine()
      }
    }
    let output = html(chart)
    _expectEqual(output.components(separatedBy: "data-chart-mark=\"rectangle\"").count - 1, 4, "Two bands plus a marker for each, as neither range starts at the first reading")
    _expectEqual(output.components(separatedBy: "<mask ").count - 1, 2, "Each band carries its own mask")
    _expectTrue(output.contains("data-chart-annotation"), "The view annotation is realized")
  }

  @Test
  func testSalesHistoryAxisWithIndexedLabelsAndPlotStyle() {
    let days = (0..<5).map { Date(timeIntervalSince1970: Double($0) * 86_400) }
    let chart = Chart {
      ForEach(days, id: \.self) { day in
        LineMark(x: .value("Day", day), y: .value("Sales", Int(day.timeIntervalSince1970 / 86_400) * 3 + 10))
      }
    }
    .chartLegend(position: .top)
    .chartYScale(domain: .automatic(includesZero: false))
    .chartXAxis {
      AxisMarks(values: .automatic(roundLowerBound: false, roundUpperBound: false)) { value in
        if value.index < value.count - 1 {
          AxisValueLabel()
        }
        AxisTick()
        AxisGridLine()
      }
    }
    let node = chart._render(in: _RenderContext())
    var labels = 0, ticks = 0, grids = 0
    func walk(_ node: _RenderNode) {
      if node.attributes["data-chart-axis-label"] == "x" { labels += 1 }
      if node.attributes["data-chart-axis-tick"] == "x" { ticks += 1 }
      if node.attributes["data-chart-axis-grid"] == "x" { grids += 1 }
      node.children.forEach(walk)
    }
    walk(node)
    _expectTrue(ticks > 1)
    _expectEqual(ticks, grids)
    _expectEqual(labels, ticks - 1, "The last mark has no label")
  }

  private static func nodes(markedAs kind: String, in root: _RenderNode) -> [_RenderNode] {
    var found: [_RenderNode] = []
    func walk(_ node: _RenderNode) {
      if node.attributes["data-chart-mark"] == kind { found.append(node) }
      node.children.forEach(walk)
    }
    walk(root)
    return found
  }

  private static func firstChild(_ tag: String, of node: _RenderNode) -> _RenderNode? {
    if case .element(let name) = node.kind, name == tag { return node }
    for child in node.children { if let match = firstChild(tag, of: child) { return match } }
    return nil
  }

  @Test
  func testDomainRangeStyleScaleColorsSeriesInOrderAndHiddenLegendIsOmitted() {
    let chart = Chart {
      PointMark(x: .value("Day", 1), y: .value("Count", 2))
        .foregroundStyle(by: .value("Series", "A"))
      PointMark(x: .value("Day", 2), y: .value("Count", 4))
        .foregroundStyle(by: .value("Series", "B"))
    }
    .chartForegroundStyleScale(domain: ["A", "B", "C"], range: [.purple, .orange])
    .chartLegend(.hidden)
    .chartYAxisLabel(Text("Items"))

    let output = html(chart)
    _expectTrue(output.contains("fill: \(Color.purple.cssValue)"), "The first domain value takes the first range color")
    _expectTrue(output.contains("fill: \(Color.orange.cssValue)"), "The second domain value takes the second range color")
    _expectFalse(output.contains("data-chart-legend"), "chartLegend(.hidden) suppresses the legend")
    _expectTrue(output.contains("Items"), "A Text axis label is rendered as its string")
  }

  @Test
  func testVerticalRuleSpansThePlotWithClampedStyle() {
    let chart = Chart {
      PointMark(x: .value("Day", 0), y: .value("Count", 0))
      PointMark(x: .value("Day", 10), y: .value("Count", 10))
      RuleMark(x: .value("Day", 5))
        .foregroundStyle(.linearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
        .lineStyle(lineWidth: 0.1)
        .opacity(3)
    }
    let rules = Self.nodes(markedAs: "rule", in: chart._render(in: _RenderContext()))
    _expectEqual(rules.count, 1)
    guard let rule = rules.first, let line = Self.firstChild("line", of: rule) else {
      _fail("The rule renders an SVG line")
      return
    }
    _expectEqual(line.attributes["x1"], line.attributes["x2"], "An x rule is vertical")
    _expectNotEqual(line.attributes["y1"], line.attributes["y2"])
    _expectEqual(line.attributes["stroke-width"], "0.5", "Line width is clamped to half a point")
    _expectEqual(line.attributes["opacity"], "1", "Opacity is clamped to one")
    _expectTrue(line.styles["stroke"]?.contains("url(#swc-grad-") == true, "A gradient rule strokes with an SVG gradient")
  }

  @Test
  func testRectangleDimensionsScaleWithTheCategoryBand() {
    let chart = Chart {
      RectangleMark(x: .value("Kind", "full"), y: .value("Value", 1), width: .ratio(1), height: .fixed(10))
      RectangleMark(x: .value("Kind", "half"), y: .value("Value", 1), width: .ratio(0.5), height: .fixed(10))
      RectangleMark(x: .value("Kind", "inset"), y: .value("Value", 1), width: .inset(5), height: .fixed(10))
    }
    let rectangles = Self.nodes(markedAs: "rectangle", in: chart._render(in: _RenderContext()))
    let widths = rectangles.compactMap { Self.firstChild("rect", of: $0)?.attributes["width"] }.compactMap(Double.init)
    let heights = rectangles.compactMap { Self.firstChild("rect", of: $0)?.attributes["height"] }.compactMap(Double.init)
    _expectEqual(widths.count, 3)
    guard widths.count == 3 else { return }
    _expectEqual(widths[1], widths[0] / 2, accuracy: 0.01)
    _expectEqual(widths[2], widths[0] - 10, accuracy: 0.01)
    _expectEqual(heights, [10, 10, 10])
  }
}

import Foundation
import Testing
import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebCharts
import SwiftUIWebHTML

@Suite
@MainActor
final class ChartRenderingTests {
  private struct Sample: Hashable {
    let day: Int
    let value: Double
    let group: String
  }

  @Test
  func testSVGChartContainsMarksAxesAndLegend() {
    let samples = [
      Sample(day: 1, value: 2, group: "A"),
      Sample(day: 2, value: 4, group: "A"),
      Sample(day: 1, value: 3, group: "B"),
      Sample(day: 2, value: 5, group: "B")
    ]
    let chart = Chart(samples) { sample in
      LineMark(
        x: .value("Day", sample.day),
        y: .value("Value", sample.value)
      )
      .foregroundStyle(by: .value("Series", sample.group))
    }
    .chartXAxis(.visible)
    .chartYAxis(.visible)
    .chartLegend(position: .bottom)

    let html = StaticHTMLFiberRenderer().render(chart)
    _expectTrue(html.contains("<svg"))
    _expectTrue(html.contains("data-chart-mark"))
    _expectTrue(html.contains("data-chart-legend"))
    _expectTrue(html.contains("Day"))
    _expectTrue(html.contains("Series"))
  }

  @Test
  func testSelectionInstallsAccessibleHitTarget() {
    let selection = Binding<String?>(get: { nil }, set: { _ in })
    let chart = Chart {
      PointMark(x: .value("Day", "Mon"), y: .value("Value", 4))
    }
    .chartXSelection(value: selection)
    let node = chart._render(in: _RenderContext())
    _expectEqual(node.kind, .element("div"))
    let svg = node.children.first
    _expectNotNil(svg)
    func containsSelectionTarget(_ node: _RenderNode) -> Bool {
      node.events["click"] != nil || node.children.contains(where: containsSelectionTarget)
    }
    _expectTrue(svg.map(containsSelectionTarget) == true)
  }

  @Test
  func testMarkFamiliesAndAnnotationsRenderAsSVGPrimitives() {
    let chart = Chart {
      BarMark(x: .value("Category", "A"), y: .value("Value", 3)).foregroundStyle(.blue)
      AreaMark(x: .value("Category", "A"), yStart: .value("Low", 1), yEnd: .value("High", 4)).foregroundStyle(.green)
      PointMark(x: .value("Category", "A"), y: .value("Value", 3)).annotation { Text("peak") }
      RuleMark(y: .value("Goal", 2)).foregroundStyle(.red)
    }
    let html = StaticHTMLFiberRenderer().render(chart)
    _expectTrue(html.contains("<rect"))
    _expectTrue(html.contains("<circle"))
    _expectTrue(html.contains("<line"))
    _expectTrue(html.contains("<path"))
    _expectTrue(html.contains("peak"))
  }

  @Test
  func testPlottableValuesPreserveNumericDateAndCategoricalSemantics() {
    let numbers = [
      ChartValue.value("Float", Float(1.25)),
      ChartValue.value("Int", 2),
      ChartValue.value("Int8", Int8(3)),
      ChartValue.value("Int16", Int16(4)),
      ChartValue.value("Int32", Int32(5)),
      ChartValue.value("Int64", Int64(6)),
      ChartValue.value("UInt", UInt(7)),
      ChartValue.value("UInt8", UInt8(8)),
      ChartValue.value("UInt16", UInt16(9)),
      ChartValue.value("UInt32", UInt32(10)),
      ChartValue.value("UInt64", UInt64(11))
    ]
    _expectEqual(numbers.compactMap(\.numericValue), [1.25, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

    let date = ChartValue.value("Time", Date(timeIntervalSince1970: 42))
    _expectEqual(date.numericValue, 42)
    let text = ChartValue.value("Category", "Monday")
    let substring = ChartValue.value("Short", "weekdays"[...].prefix(3))
    _expectEqual(text.kind, .category("Monday"))
    _expectEqual(substring.rawValue, "wee")

    struct DescribedCategory: Hashable, CustomStringConvertible {
      var description: String { "custom-category" }
    }
    _expectEqual(ChartValue.value("Custom", DescribedCategory()).rawValue, "custom-category")
  }

  @Test
  func testChartModifiersControlDomainsAxesLabelsAndCategoricalLegend() {
    struct Point {
      let id: String
      let day: Int
      let count: Double
      let series: String
    }
    let points = [
      Point(id: "a", day: 1, count: 2, series: "A"),
      Point(id: "b", day: 2, count: 4, series: "B")
    ]
    let chart = Chart(points, id: \.id) { point in
      PointMark(x: .value("Day", point.day), y: .value("Count", point.count))
        .foregroundStyle(by: .value("Series", point.series))
    }
    .chartXAxis(AxisMarks(.visible, values: [1, 2]))
    .chartYAxis(AxisMarks(.visible, values: [0, 5]))
    .chartXAxisLabel(Text("Week"))
    .chartYAxisLabel("Items")
    .chartXScale(domain: 0...5)
    .chartYScale(domain: 0...10)
    .chartForegroundStyleScale(["A": .red, "B": .blue])
    .chartLegend(position: .trailing, alignment: .center, spacing: 4)

    let html = StaticHTMLFiberRenderer().render(chart)
    _expectTrue(html.contains("aria-label=\"Chart of Day\""))
    _expectTrue(html.contains("Week"))
    _expectTrue(html.contains("Items"))
    _expectTrue(html.contains("data-chart-legend=\"true\""))
    _expectTrue(html.contains("Series"))
    _expectTrue(html.contains("fill: \(Color.red.cssValue)"), "The explicit foreground scale must reach its series")
  }

  @Test
  func testChartSelectionsUpdateTypedBindingsAndExposeAccessibleTargets() {
    var selectedDay: String?
    let dayBinding = Binding<String?>(get: { selectedDay }, set: { selectedDay = $0 })
    let xChart = Chart {
      PointMark(x: .value("Day", "Tue"), y: .value("Count", 7))
    }
    .chartXSelection(value: dayBinding)
    let xNode = xChart._render(in: _RenderContext())
    let xTarget = chartHitTarget(in: xNode)
    _expectEqual(xTarget?.attributes["role"], "button")
    _expectEqual(xTarget?.attributes["tabindex"], "0")
    _expectEqual(xTarget?.attributes["aria-label"], "Day: Tue")
    xTarget?.events["click"]?.action()
    _expectEqual(selectedDay, "Tue")

    var selectedCount: Int?
    let countBinding = Binding<Int?>(get: { selectedCount }, set: { selectedCount = $0 })
    let yNode = Chart {
      BarMark(x: .value("Day", "Tue"), y: .value("Count", 7))
    }
    .chartYSelection(value: countBinding)
    ._render(in: _RenderContext())
    chartHitTarget(in: yNode)?.events["click"]?.action()
    _expectEqual(selectedCount, 7)
  }

  @Test
  func testChartContentBuilderHandlesBothBranchesOptionalsAndCollections() {
    func conditionalChart(selectLine: Bool) -> _RenderNode {
      Chart {
        if selectLine {
          LineMark(x: .value("X", 1), y: .value("Y", 2))
        } else {
          PointMark(x: .value("X", 1), y: .value("Y", 2))
        }
      }._render(in: _RenderContext())
    }
    _expectTrue(chartMarks(conditionalChart(selectLine: true)).contains { $0.attributes["data-chart-mark"] == "line" })
    _expectTrue(chartMarks(conditionalChart(selectLine: false)).contains { $0.attributes["data-chart-mark"] == "point" })

    func optionalChart(includeArea: Bool) -> _RenderNode {
      let area: AreaMark? = includeArea
        ? AreaMark(x: .value("X", 1), y: .value("Y", 2))
        : nil
      return Chart {
        if let area { area }
      }._render(in: _RenderContext())
    }
    _expectTrue(chartMarks(optionalChart(includeArea: true)).contains { $0.attributes["data-chart-mark"] == "area" })
    _expectFalse(chartMarks(optionalChart(includeArea: false)).contains { $0.attributes["data-chart-mark"] == "area" })

    let bars = Chart {
      for value in [1, 2, 3] {
        BarMark(x: .value("X", value), y: .value("Y", value * 2))
      }
    }._render(in: _RenderContext())
    _expectEqual(chartMarks(bars).filter { $0.attributes["data-chart-mark"] == "bar" }.count, 3)
  }

}

@Suite
@MainActor
final class ChartBenchmarks {
  private struct Point: Hashable { let x: Int; let y: Double }

  @Test
  func testSmallDatasetRenderBenchmark() {
    let points = (0..<32).map { Point(x: $0, y: Double(($0 * 17) % 23)) }
    let chart = Chart(points) { point in
      LineMark(x: .value("X", point.x), y: .value("Y", point.y))
    }
    _measure { _ = chart._render(in: _RenderContext()) }
  }

  @Test
  func testLargeDatasetRenderBenchmark() {
    let points = (0..<5_000).map { Point(x: $0, y: Double(($0 * 7919) % 997)) }
    let chart = Chart(points) { point in
      PointMark(x: .value("X", point.x), y: .value("Y", point.y)).symbolSize(12)
    }
    _measure { _ = chart._render(in: _RenderContext()) }
  }
}

/// The children of a rendered chart's SVG (the chart sits in the frame and GeometryReader that give it its size).
private func chartMarks(_ node: _RenderNode) -> [_RenderNode] {
  func svg(_ node: _RenderNode) -> _RenderNode? {
    if node.classes.contains("chart-svg") { return node }
    for child in node.children { if let found = svg(child) { return found } }
    return nil
  }
  return svg(node)?.children ?? []
}

private func chartHitTarget(in node: _RenderNode) -> _RenderNode? {
  if node.events["click"] != nil { return node }
  for child in node.children {
    if let target = chartHitTarget(in: child) { return target }
  }
  return nil
}

import Testing
import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebCharts
import SwiftUIWebHTML

/// Swift Charts' look, measured on an iPad (Food Truck's forecast): marks without a style take the app's accent colour,
/// gradients blend in OKLab, axis labels are 10-point secondary text and grid lines are separator hairlines, dashed
/// across the x axis.
@Suite
@MainActor
struct ChartAppleStyleTests {
  @Test
  func anUnstyledMarkTakesTheAppsAccentColour() {
    let html = StaticHTMLFiberRenderer().render(
      Chart { BarMark(x: .value("Day", "Mon"), y: .value("Sales", 3)) }.frame(width: 200, height: 120)
    )
    #expect(html.contains("var(--tint-color, light-dark(#0088FF, #0091FF))"), "\(html)")
  }

  @Test
  func aGradientIsBlendedInOKLab() {
    let html = StaticHTMLFiberRenderer().render(
      Chart {
        AreaMark(x: .value("Hour", 0), y: .value("Degrees", 60))
          .foregroundStyle(.linearGradient(colors: [.teal, .yellow], startPoint: .bottom, endPoint: .top))
        AreaMark(x: .value("Hour", 1), y: .value("Degrees", 80))
          .foregroundStyle(.linearGradient(colors: [.teal, .yellow], startPoint: .bottom, endPoint: .top))
      }.frame(width: 200, height: 120)
    )
    #expect(html.contains("color-mix(in oklab, \(Color.teal.cssValue) 50%, \(Color.yellow.cssValue))"), "\(html)")
  }

  @Test
  func axesAreSecondaryLabelsOverSeparatorHairlines() {
    let html = StaticHTMLFiberRenderer().render(
      Chart { LineMark(x: .value("X", 0), y: .value("Y", 1)); LineMark(x: .value("X", 10), y: .value("Y", 5)) }
        .chartXAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel() } }
        .frame(width: 300, height: 160)
    )
    #expect(html.contains("font-size=\"10\""), "\(html)")
    #expect(html.contains("fill: light-dark(rgb(60 60 67 / 0.6), rgb(235 235 245 / 0.6))"), "\(html)")
    #expect(html.contains("stroke: light-dark(rgb(60 60 67 / 0.29), rgb(84 84 88 / 0.6))"), "\(html)")
    #expect(html.contains("stroke-dasharray=\"3 3\""), "the x axis grid is dashed")
  }

  /// The x coordinates of the y axis grid lines' ends: the plot's left and right edges.
  private func plotEdges(_ html: String) -> (Double, Double)? {
    guard let range = html.range(of: "data-chart-axis-grid=\"y\"") else { return nil }
    let tagEnd = html[range.upperBound...].firstIndex(of: ">") ?? html.endIndex
    let tag = html[html[..<range.lowerBound].lastIndex(of: "<")!..<tagEnd]
    func value(_ name: String) -> Double? {
      guard let start = tag.range(of: "\(name)=\"") else { return nil }
      return Double(tag[start.upperBound...].prefix { $0 != "\"" })
    }
    guard let x1 = value("x1"), let x2 = value("x2") else { return nil }
    return (x1, x2)
  }

  @Test
  func longLabelsLeaveThePlotAPositiveWidth() {
    let html = StaticHTMLFiberRenderer().render(
      Chart { LineMark(x: .value("X", 0), y: .value("Y", 1)); LineMark(x: .value("X", 1), y: .value("Y", 2)) }
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel("A label far too long for a chart this narrow ever") } }
        .frame(width: 200, height: 120)
    )
    let edges = plotEdges(html)
    #expect(edges != nil, "\(html)")
    if let (left, right) = edges { #expect(right - left >= 100, "plot from \(left) to \(right)") }
  }

  @Test
  func aLegendUnderTheChartHasARowBelowTheXLabels() {
    let html = StaticHTMLFiberRenderer().render(
      Chart {
        BarMark(x: .value("Day", "Mon"), y: .value("Sales", 3)).foregroundStyle(by: .value("City", "London"))
        BarMark(x: .value("Day", "Tue"), y: .value("Sales", 5)).foregroundStyle(by: .value("City", "Paris"))
      }
      .chartLegend(position: .bottom)
      .frame(width: 300, height: 200)
    )
    // The legend's baseline is at least 15 points under the x labels' (its swatches are 12 tall).
    func leadingNumber(_ text: Substring) -> Double? { Double(text.prefix { "0123456789.".contains($0) }) }
    var legendY: Double?
    if let legend = html.range(of: "data-chart-legend"), let comma = html[legend.upperBound...].range(of: ", ") {
      legendY = leadingNumber(html[comma.upperBound...])
    }
    var labelY: Double?
    if let mon = html.range(of: ">Mon<"), let open = html[..<mon.lowerBound].lastIndex(of: "<"),
       let y = html[open..<mon.lowerBound].range(of: " y=\"") {
      labelY = leadingNumber(html[y.upperBound...])
    }
    #expect(legendY != nil && labelY != nil, "\(html)")
    if let legendY, let labelY { #expect(legendY - labelY >= 15, "legend at \(legendY), x labels at \(labelY)") }
  }

  @Test
  func aYAxisTitleHasRoomBesideLeadingLabels() {
    let html = StaticHTMLFiberRenderer().render(
      Chart { LineMark(x: .value("X", 0), y: .value("Y", 100)); LineMark(x: .value("X", 1), y: .value("Y", 200)) }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
        .chartYAxisLabel("Sales")
        .frame(width: 300, height: 160)
    )
    // The title is drawn at x = 12; the labels' column ("200": 10 + 17.4 + 4 points) starts after its 24 points.
    if let (left, _) = plotEdges(html) { #expect(left >= 24 + 31, "plot starts at \(left)") } else { Issue.record("no grid line: \(html)") }
  }
}

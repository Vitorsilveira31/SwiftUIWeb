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
}

import SwiftUIWebCore
import Testing
@testable import SwiftUIWebCharts

/// The plot keeps a positive width however narrow the chart and however wide its labels.
@Suite
struct ChartLayoutMarginTests {
  @Test(arguments: [30.0, 60.0, 200.0, 640.0])
  func thePlotKeepsAFifthOfTheChart(width: Double) {
    for leading in [false, true] {
      let layout = _ChartLayout(size: CGSize(width: width, height: 100), yAxisLeading: leading, labelColumn: 400, edgeMargin: 24)
      #expect(layout.plotWidth >= width * 0.2 - 0.001, "width \(width), leading \(leading): plot \(layout.plotWidth)")
    }
  }

  @Test
  func shortLabelsKeepTheirOwnRoom() {
    let layout = _ChartLayout(size: CGSize(width: 400, height: 200), labelColumn: 37, edgeMargin: 0)
    #expect(layout.right == 37)
    #expect(layout.left == 0)
  }
}

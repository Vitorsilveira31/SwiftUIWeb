import Foundation
import Testing
import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebCharts
import SwiftUIWebHTML

/// An automatic domain extends to the automatic marks its axis asks for, as in Swift Charts: Food Truck's forecast asks for
/// six marks at least five degrees apart without rounding the lower bound, and its temperatures (55 to 83) span 55 to 85.
@Suite
@MainActor
struct ChartAutomaticDomainTests {
  @Test
  func theDomainFollowsTheMarksTheAxisAsksFor() {
    let temperatures: [(Int, Double)] = [(0, 63), (3, 77), (6, 83), (9, 79), (12, 66), (15, 61), (18, 57), (21, 55), (24, 62)]
    let html = StaticHTMLFiberRenderer().render(
      Chart {
        ForEach(temperatures, id: \.0) { hour, degrees in
          LineMark(x: .value("Hour", hour), y: .value("Temperature", degrees))
        }
      }
      .chartYScale(domain: .automatic(includesZero: false))
      .chartYAxis {
        AxisMarks(values: .automatic(minimumStride: 5, desiredCount: 6, roundLowerBound: false)) { value in
          AxisValueLabel("\(Int(value.as(Double.self)!))°F")
        }
      }
      .frame(width: 400, height: 240)
    )
    for label in ["55°F", "60°F", "70°F", "85°F"] { #expect(html.contains(">\(label)<"), "\(label) missing") }
    #expect(!html.contains(">50°F<"))
    #expect(!html.contains(">90°F<"))
  }

  @Test
  func areaMarksBetweenALowAndEachValueSpanTheSameDomain() {
    let temperatures: [(Int, Double)] = [(0, 63), (3, 77), (6, 83), (9, 79), (12, 66), (15, 61), (18, 57), (21, 55), (24, 62)]
    let html = StaticHTMLFiberRenderer().render(
      Chart {
        ForEach(temperatures, id: \.0) { hour, degrees in
          // Food Truck's low is the coolest hour less two degrees, and its night bars start half a degree under it.
          AreaMark(x: .value("Hour", hour), yStart: .value("Temperature", 53), yEnd: .value("Temperature", degrees), series: .value("Series", 0))
        }
        RectangleMark(x: .value("Date", 12), yStart: .value("Temperature", 52.5), yEnd: .value("Temperature", 66.5), width: .fixed(4))
      }
      .chartYScale(domain: .automatic(includesZero: false))
      .chartYAxis {
        AxisMarks(values: .automatic(minimumStride: 5, desiredCount: 6, roundLowerBound: false)) { value in
          AxisValueLabel("\(Int(value.as(Double.self)!))°F")
          AxisTick()
          AxisGridLine()
        }
      }
      .frame(width: 400, height: 240)
    )
    let labels = html.components(separatedBy: "°F<").dropLast().compactMap { $0.split(separator: ">").last.map(String.init) }
    #expect(labels == ["55", "60", "65", "70", "75", "80", "85"], "\(labels)")
  }
}

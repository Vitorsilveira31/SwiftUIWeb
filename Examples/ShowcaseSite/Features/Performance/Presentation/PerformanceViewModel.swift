import SwiftUIWeb

/// The performance page's state: the results and the CPU rate shown.
@MainActor @Observable
final class PerformanceViewModel {
  let results: PerformanceResultsVO
  var cpu: Int

  init(load: any LoadPerformanceResultsUseCase) {
    results = load.execute()
    cpu = results.rates.first?.cpu ?? 1
  }

  var rates: [Int] { results.rates.map(\.cpu) }

  /// The cold loads measured under each network profile: they do not depend on the CPU rate shown.
  var networks: [PerformanceNetworkVO] { results.networks }

  /// The metrics of the rate shown, each with the length of its two bars.
  var rows: [PerformanceRowVO] {
    guard let rate = results.rates.first(where: { $0.cpu == cpu }) else { return [] }
    return rate.metrics.map { PerformanceViewModel.row(for: $0, swiftUIWebThrottled: rate.swiftUIWebThrottled) }
  }

  /// How many metrics React took more, less, or no different time or amount on, at the rate shown. Where SwiftUIWeb's worker was not
  /// throttled, the count uses the verdict against the main thread, the one side that was throttled at that rate.
  var tally: (reactHigher: Int, reactLower: Int, same: Int) {
    var counts = (reactHigher: 0, reactLower: 0, same: 0)
    for row in rows {
      switch row.swiftUIWebThrottled ? row.metric.verdict : row.metric.mainThreadVerdict {
      case .reactHigher: counts.reactHigher += 1
      case .reactLower: counts.reactLower += 1
      case .same, .tooFewSamples: counts.same += 1
      }
    }
    return counts
  }

  /// The measurements the page leads with, in the order they are shown: what a visitor feels first (loading, size), then what
  /// the framework does to the page (nodes), then how it behaves when used (typing, blocking). The cold load on slow 4G is the sixth.
  static let highlightIDs = ["load", "transfer", "nodes", "type", "blocking"]

  var highlights: [PerformanceRowVO] {
    PerformanceViewModel.highlightIDs.compactMap { id in rows.first { $0.metric.id == id } }
  }

  /// The cold load on the first slow network profile, the number that matters most to a first-time visitor.
  var slowNetworkHighlight: PerformanceRowVO? {
    networks.first?.metrics.first { $0.id == "load" }.map { PerformanceViewModel.row(for: $0) }
  }

  static func row(for metric: PerformanceMetricVO, swiftUIWebThrottled: Bool = true) -> PerformanceRowVO {
    let longest = max(metric.swiftUIWeb, metric.mainThread, metric.react, metric.reactVirtual)
    return PerformanceRowVO(
      metric: metric,
      swiftUIWebShare: longest == 0 ? 0 : metric.swiftUIWeb / longest,
      mainThreadShare: longest == 0 ? 0 : metric.mainThread / longest,
      reactShare: longest == 0 ? 0 : metric.react / longest,
      percent: percent(of: metric.react, over: metric.swiftUIWeb),
      mainThreadPercent: percent(of: metric.react, over: metric.mainThread),
      swiftUIWebThrottled: swiftUIWebThrottled,
      reactVirtualShare: longest == 0 ? 0 : metric.reactVirtual / longest,
      reactVirtualPercent: percent(of: metric.reactVirtual, over: metric.swiftUIWeb)
    )
  }

  private static func percent(of react: Double, over other: Double) -> Int {
    other == 0 ? 0 : Int(((react - other) / other * 100).rounded())
  }
}

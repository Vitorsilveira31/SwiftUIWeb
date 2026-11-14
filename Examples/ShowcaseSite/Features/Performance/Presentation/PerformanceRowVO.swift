/// One metric as the page draws it: the three medians, how long each bar is, and what the comparisons concluded.
struct PerformanceRowVO {
  let metric: PerformanceMetricVO
  /// The share of the longest bar each side fills, from 0 to 1.
  let swiftUIWebShare: Double
  let mainThreadShare: Double
  let reactShare: Double
  /// React's median against SwiftUIWeb's, as a percentage (positive: React is higher).
  let percent: Int
  /// The same against SwiftUIWeb with its Swift on the main thread.
  let mainThreadPercent: Int
  /// False when the CPU slowdown did not reach SwiftUIWeb's worker: its bar and its verdict against React do not stand for that rate.
  let swiftUIWebThrottled: Bool
  /// The virtualized React's share of the longest bar, and its change against SwiftUIWeb as a percentage.
  let reactVirtualShare: Double
  let reactVirtualPercent: Int
}

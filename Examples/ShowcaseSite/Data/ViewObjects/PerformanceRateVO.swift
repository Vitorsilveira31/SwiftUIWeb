/// The metrics measured with the CPU slowed by `cpu` times (1 is the machine as it is).
struct PerformanceRateVO {
  let cpu: Int
  /// Whether the slowdown reached the worker that runs SwiftUIWeb's app. Chromium does not throttle a worker, so at a rate above 1
  /// this is false and that side ran at full speed: it is shown as such and not compared with React.
  let swiftUIWebThrottled: Bool
  let metrics: [PerformanceMetricVO]
}

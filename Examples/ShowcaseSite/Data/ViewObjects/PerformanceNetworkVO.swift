/// The cold load measured under one network profile: the conditions it was emulated with, and the metrics of the load.
struct PerformanceNetworkVO {
  let label: String
  /// The round trip added to each request, in milliseconds.
  let latency: Int
  /// The download and upload bandwidth, in megabits and kilobits per second.
  let downloadMbps: Double
  let uploadKbps: Int
  let metrics: [PerformanceMetricVO]
}

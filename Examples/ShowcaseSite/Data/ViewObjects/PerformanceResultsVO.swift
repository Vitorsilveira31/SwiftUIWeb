/// Everything the comparison produced, and the conditions it was measured in.
struct PerformanceResultsVO {
  let date: String
  let machine: String
  let browser: String
  let rounds: Int
  let rates: [PerformanceRateVO]
  /// The network profiles measured (cold load only), in the order they were run.
  let networks: [PerformanceNetworkVO]
}

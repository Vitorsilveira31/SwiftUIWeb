/// Where the results of the comparison come from.
protocol PerformanceResultsRepository {
  func results() -> PerformanceResultsVO
}

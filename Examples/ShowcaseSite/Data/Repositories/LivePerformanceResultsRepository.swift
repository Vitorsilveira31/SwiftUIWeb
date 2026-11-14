/// The results measured by `Tools/compare-react.mjs`, published into `PerformanceResultsData` by
/// `Tools/publish-react-comparison.mjs`.
struct LivePerformanceResultsRepository: PerformanceResultsRepository {
  func results() -> PerformanceResultsVO { PerformanceResultsData.results }
}

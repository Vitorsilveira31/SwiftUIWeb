protocol LoadPerformanceResultsUseCase { func execute() -> PerformanceResultsVO }

struct DefaultLoadPerformanceResultsUseCase: LoadPerformanceResultsUseCase {
  let repository: any PerformanceResultsRepository

  func execute() -> PerformanceResultsVO { repository.results() }
}

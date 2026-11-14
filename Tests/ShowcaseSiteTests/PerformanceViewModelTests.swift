import Testing
@testable import ShowcaseSite

private struct StubLoadPerformanceResults: LoadPerformanceResultsUseCase {
  let results: PerformanceResultsVO
  func execute() -> PerformanceResultsVO { results }
}

@MainActor
struct PerformanceViewModelTests {
  private func metric(_ id: String, swift: Double, react: Double, main: Double? = nil, _ verdict: PerformanceVerdict, unit: String = "ms") -> PerformanceMetricVO {
    PerformanceMetricVO(
      id: id, unit: unit, swiftUIWeb: swift, mainThread: main ?? swift, react: react,
      swiftUIWebSpread: 0, mainThreadSpread: 0, reactSpread: 0, verdict: verdict, mainThreadVerdict: verdict,
      reactVirtual: react, reactVirtualSpread: 0, reactVirtualVerdict: verdict
    )
  }

  private func makeModel() -> PerformanceViewModel {
    let results = PerformanceResultsVO(
      date: "2026-10-28", machine: "machine", browser: "browser", rounds: 15,
      rates: [
        PerformanceRateVO(cpu: 1, swiftUIWebThrottled: true, metrics: [
          metric("type", swift: 10, react: 20, .reactHigher),
          metric("load", swift: 40, react: 20, .reactLower),
          metric("add", swift: 8, react: 8.2, .same),
        ]),
        PerformanceRateVO(cpu: 4, swiftUIWebThrottled: false, metrics: [metric("type", swift: 40, react: 100, .reactHigher)]),
      ],
      networks: []
    )
    return PerformanceViewModel(load: StubLoadPerformanceResults(results: results))
  }

  @Test func itStartsOnTheFirstRate() {
    let model = makeModel()
    #expect(model.cpu == 1)
    #expect(model.rates == [1, 4])
    #expect(model.rows.map(\.metric.id) == ["type", "load", "add"])
  }

  @Test func theHighlightsAreTheLeadingMetricsInTheirOwnOrderAndSkipWhatWasNotMeasured() {
    let model = makeModel()
    // The stub measured "type", "load" and "add": only the first two are headline metrics, shown in the order of
    // `highlightIDs` (load before type), not in the order they were measured.
    #expect(model.highlights.map(\.metric.id) == ["load", "type"])
    #expect(model.slowNetworkHighlight == nil)
  }

  @Test func anotherRateShowsItsOwnMetrics() {
    let model = makeModel()
    model.cpu = 4
    #expect(model.rows.map(\.metric.id) == ["type"])
    #expect(model.rows.first?.metric.swiftUIWeb == 40)
  }

  @Test func anUnknownRateShowsNothing() {
    let model = makeModel()
    model.cpu = 8
    #expect(model.rows.isEmpty)
  }

  @Test func theLongerSideFillsItsBarAndTheOtherIsInProportion() {
    let rows = makeModel().rows
    #expect(rows[0].reactShare == 1)
    #expect(rows[0].swiftUIWebShare == 0.5)
    #expect(rows[1].swiftUIWebShare == 1)
    #expect(rows[1].reactShare == 0.5)
  }

  @Test func theMainThreadBarIsInProportionToo() {
    let row = PerformanceViewModel.row(for: metric("a", swift: 40, react: 20, main: 10, .reactLower))
    #expect(row.mainThreadShare == 0.25)
    #expect(row.mainThreadPercent == 100)
  }

  @Test func aMetricOfZeroOnBothSidesHasEmptyBars() {
    let row = PerformanceViewModel.row(for: metric("blocking", swift: 0, react: 0, .same))
    #expect(row.swiftUIWebShare == 0)
    #expect(row.reactShare == 0)
    #expect(row.percent == 0)
  }

  @Test func theChangeIsReactAgainstSwiftUIWebInPercent() {
    #expect(PerformanceViewModel.row(for: metric("a", swift: 20, react: 30, .reactHigher)).percent == 50)
    #expect(PerformanceViewModel.row(for: metric("a", swift: 40, react: 20, .reactLower)).percent == -50)
    #expect(PerformanceViewModel.row(for: metric("a", swift: 0, react: 5, .same)).percent == 0)
  }

  @Test func theTallyCountsWhatReactTookMoreLessOrAboutTheSame() {
    let tally = makeModel().tally
    #expect(tally.reactHigher == 1)
    #expect(tally.reactLower == 1)
    #expect(tally.same == 1)
  }

  @Test func theVirtualizedReactHasItsOwnShareAndChangeAgainstSwiftUIWeb() {
    let row = PerformanceViewModel.row(for: metric("a", swift: 40, react: 20, .reactLower))
    #expect(row.reactVirtualShare == 0.5)
    #expect(row.reactVirtualPercent == -50)
  }

  @Test func aWorkerThatWasNotThrottledIsNotComparedWithReact() {
    let model = makeModel()
    model.cpu = 4
    #expect(model.rows.first?.swiftUIWebThrottled == false)
    #expect(model.rows.first?.metric.swiftUIWeb == 40)
  }

  @Test func theTallyOfAnUnthrottledRateUsesTheMainThreadVerdict() {
    let split = PerformanceMetricVO(
      id: "type", unit: "ms", swiftUIWeb: 40, mainThread: 90, react: 100,
      swiftUIWebSpread: 0, mainThreadSpread: 0, reactSpread: 0, verdict: .same, mainThreadVerdict: .reactHigher,
      reactVirtual: 60, reactVirtualSpread: 0, reactVirtualVerdict: .reactHigher
    )
    let results = PerformanceResultsVO(
      date: "2026-10-28", machine: "machine", browser: "browser", rounds: 15,
      rates: [PerformanceRateVO(cpu: 4, swiftUIWebThrottled: false, metrics: [split])],
      networks: []
    )
    let model = PerformanceViewModel(load: StubLoadPerformanceResults(results: results))
    model.cpu = 4
    #expect(model.tally.reactHigher == 1)
    #expect(model.tally.same == 0)
  }
}

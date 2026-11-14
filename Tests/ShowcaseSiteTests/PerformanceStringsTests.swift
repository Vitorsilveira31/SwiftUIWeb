import Testing
@testable import ShowcaseSite

struct PerformanceStringsTests {
  @Test func everyMetricTheComparisonMeasuredHasAName() {
    for rate in PerformanceResultsData.results.rates {
      for metric in rate.metrics {
        for language in SiteLanguage.allCases {
          let name = PerformanceStrings.metric(metric.id, language)
          #expect(name != metric.id, "\(metric.id) has no \(language) name")
        }
      }
    }
  }

  @Test func theResultsCarryTheirConditions() {
    let results = PerformanceResultsData.results
    #expect(!results.rates.isEmpty)
    #expect(results.rounds >= 10)
    #expect(!results.date.isEmpty && !results.machine.isEmpty && !results.browser.isEmpty)
    #expect(results.rates.first?.cpu == 1)
  }

  @Test func numbersAreShownToOneDecimalOrWhole() {
    #expect(PerformanceStrings.value(12.34, unit: "ms") == "12.3 ms")
    #expect(PerformanceStrings.value(550.46, unit: "KB") == "550.5 KB")
    #expect(PerformanceStrings.value(303, unit: "") == "303")
    #expect(PerformanceStrings.value(0, unit: "ms") == "0.0 ms")
  }

  @Test func aVerdictNamesReactAndTheSizeWithoutASign() {
    #expect(PerformanceStrings.verdict(.reactHigher, percent: 100, .en) == "React: 100% more")
    #expect(PerformanceStrings.verdict(.reactLower, percent: -50, .pt) == "React: 50% a menos")
    #expect(PerformanceStrings.mainThreadVerdict(.reactLower, percent: -30, .en) == "Against the main thread, React: 30% less")
    #expect(PerformanceStrings.mainThreadVerdict(.same, percent: 0, .pt) == "Contra a thread principal, sem diferença relevante")
  }

  @Test func theMethodAndTheCaveatsAreWrittenInBothLanguages() {
    for language in SiteLanguage.allCases {
      #expect(PerformanceStrings.method(language).count == 4)
      #expect(PerformanceStrings.caveats(language).count == 4)
    }
    #expect(PerformanceStrings.method(.pt).map(\.title) != PerformanceStrings.method(.en).map(\.title))
  }
}

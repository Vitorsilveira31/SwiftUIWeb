import Testing
@testable import SwiftUIWebCharts

/// The numbers a chart writes into its values and default axis labels.
@Suite
struct ChartNumberTests {
  @Test
  func wholeFractionalAndHugeValuesKeepTheirDigits() {
    #expect(_chartNumber(42) == "42")
    #expect(_chartNumber(-3_000_000_000) == "-3000000000")
    #expect(_chartNumber(1.25) == "1.25")
    #expect(_chartNumber(0.0004) == "0")
    // Past Int64 the value is written as Swift writes it, exponent included.
    #expect(_chartNumber(1e30) == "1e+30")
    #expect(_chartNumber(-1e300) == "-1e+300")
    #expect(_chartNumber(.infinity) == "0")
  }
}

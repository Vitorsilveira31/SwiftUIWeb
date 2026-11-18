import SwiftUIWeb

/// One of the headline measurements: its name, SwiftUIWeb's number, React's, and in a word where SwiftUIWeb stands.
struct PerformanceHighlightCard: View {
  let title: String
  let row: PerformanceRowVO
  @Environment(\.siteLanguage) private var language

  var body: some View {
    // As tall as its row, as every card of a grid is (`SiteIconRow`), whatever the length of its title.
    SiteCard(fillsHeight: true) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      Text(PerformanceStrings.value(swiftUIWebValue, unit: row.metric.unit))
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .monospacedDigit()
      Text(PerformanceStrings.reactComparison(PerformanceStrings.value(row.metric.react, unit: row.metric.unit), language))
        .font(.caption)
        .foregroundStyle(.secondary)
      PerformanceStandingBadge(standing: standing)
    }
  }

  /// The number that stands for SwiftUIWeb at the CPU rate shown: its worker's, or the main-thread bundle's where the
  /// worker was not throttled (the same rule as the tally of the whole page).
  private var swiftUIWebValue: Double {
    row.swiftUIWebThrottled ? row.metric.swiftUIWeb : row.metric.mainThread
  }

  private var standing: PerformanceVerdict {
    row.swiftUIWebThrottled ? row.metric.verdict : row.metric.mainThreadVerdict
  }
}

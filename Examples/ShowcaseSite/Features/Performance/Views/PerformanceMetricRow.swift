import SwiftUIWeb

/// One metric: what was measured, the two bars and what the comparison concluded.
struct PerformanceMetricRow: View {
  let row: PerformanceRowVO
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SiteCard {
      Text(PerformanceStrings.metric(row.metric.id, language)).font(.headline)
      PerformanceBar(
        name: PerformanceStrings.swiftUIWebName(language, throttled: row.swiftUIWebThrottled),
        share: row.swiftUIWebShare,
        text: PerformanceStrings.value(row.metric.swiftUIWeb, unit: row.metric.unit),
        tint: .blue
      )
      PerformanceBar(
        name: PerformanceStrings.mainThreadName(language),
        share: row.mainThreadShare,
        text: PerformanceStrings.value(row.metric.mainThread, unit: row.metric.unit),
        tint: .teal
      )
      PerformanceBar(
        name: PerformanceStrings.reactName(language),
        share: row.reactShare,
        text: PerformanceStrings.value(row.metric.react, unit: row.metric.unit),
        tint: .orange
      )
      PerformanceBar(
        name: PerformanceStrings.reactVirtualName(language),
        share: row.reactVirtualShare,
        text: PerformanceStrings.value(row.metric.reactVirtual, unit: row.metric.unit),
        tint: .green
      )
      Text(row.swiftUIWebThrottled ? PerformanceStrings.verdict(row.metric.verdict, percent: row.percent, language) : PerformanceStrings.notComparable(language))
        .font(.caption).foregroundStyle(.secondary)
      Text(PerformanceStrings.mainThreadVerdict(row.metric.mainThreadVerdict, percent: row.mainThreadPercent, language)).font(.caption).foregroundStyle(.secondary)
      Text(row.swiftUIWebThrottled ? PerformanceStrings.virtualVerdict(row.metric.reactVirtualVerdict, percent: row.reactVirtualPercent, language) : PerformanceStrings.notComparable(language))
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

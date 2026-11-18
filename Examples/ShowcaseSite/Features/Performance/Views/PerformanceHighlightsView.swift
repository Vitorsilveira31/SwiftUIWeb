import SwiftUIWeb

/// The page in six numbers, before the forty-odd bars below it.
struct PerformanceHighlightsView: View {
  let viewModel: PerformanceViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SiteSection(heading: PerformanceStrings.highlightsHeading(language)) {
      SiteParagraph(text: PerformanceStrings.highlightsLead(language))
      SiteCardGrid(minimumWidth: SiteLayout.statCardMinWidth) {
        ForEach(viewModel.highlights, id: \.metric.id) { row in
          PerformanceHighlightCard(title: PerformanceStrings.metric(row.metric.id, language), row: row)
        }
        if let slow = viewModel.slowNetworkHighlight {
          PerformanceHighlightCard(title: PerformanceStrings.slowLoadTitle(language), row: slow)
        }
      }
    }
  }
}

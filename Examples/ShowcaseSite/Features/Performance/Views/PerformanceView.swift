import SwiftUIWeb

/// SwiftUIWeb against React, measured: the headline numbers first, then the app, every measurement folded away, how it was
/// measured and what it does not say.
struct PerformanceView: View {
  let viewModel: PerformanceViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageScaffold {
      SitePageHeader(title: PerformanceStrings.title(language), lead: PerformanceStrings.lead(language))
      VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
        PerformanceCpuPicker(viewModel: viewModel)
        SiteParagraph(text: summary)
      }
      PerformanceHighlightsView(viewModel: viewModel)
      SiteSection(heading: PerformanceStrings.appHeading(language)) {
        SiteParagraph(text: PerformanceStrings.app(language))
        PerformanceAllMeasurements(viewModel: viewModel)
        Text(PerformanceStrings.conditions(viewModel.results, language)).font(.caption).foregroundStyle(.secondary)
      }
      PurposeSection(heading: PerformanceStrings.methodHeading(language), items: PerformanceStrings.method(language), symbol: "checkmark.circle")
      PurposeSection(heading: PerformanceStrings.caveatsHeading(language), items: PerformanceStrings.caveats(language), symbol: "info.circle", tint: SiteTheme.negative)
    }
  }

  private var summary: String {
    let tally = viewModel.tally
    return PerformanceStrings.summary(highest: tally.reactHigher, lowest: tally.reactLower, same: tally.same, language)
  }
}

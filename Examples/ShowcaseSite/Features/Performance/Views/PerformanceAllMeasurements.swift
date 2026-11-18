import SwiftUIWeb

/// Every measurement with its bars, folded away until asked for.
///
/// A header button and content in an ordinary stack, not a `DisclosureGroup`: the layout engine treats a `<details>` as one opaque
/// box and never applies the padding and widths of what is inside it, so cards in it had no padding and their bars no width. The
/// rows are made when the section opens.
struct PerformanceAllMeasurements: View {
  let viewModel: PerformanceViewModel
  @State private var isExpanded = false
  @Environment(\.siteLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
      Button { isExpanded.toggle() } label: {
        HStack {
          Text(PerformanceStrings.allMeasurements(viewModel.rows.count + networkCount, language)).font(.headline)
          Spacer(minLength: 8)
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
        }
        .padding(SiteLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius).stroke(Color.primary.opacity(0.12)))
      }
      .buttonStyle(.plain)
      .accessibilityValue(isExpanded ? PerformanceStrings.expanded(language) : PerformanceStrings.collapsed(language))
      if isExpanded {
        ForEach(viewModel.rows, id: \.metric.id) { row in PerformanceMetricRow(row: row) }
        ForEach(viewModel.networks, id: \.label) { network in
          SiteHeading(text: PerformanceStrings.networkHeading(language))
          SiteParagraph(text: PerformanceStrings.networkNote(network, language))
          ForEach(network.metrics.map { PerformanceViewModel.row(for: $0) }, id: \.metric.id) { row in PerformanceMetricRow(row: row) }
        }
      }
    }
  }

  private var networkCount: Int { viewModel.networks.reduce(0) { $0 + $1.metrics.count } }
}

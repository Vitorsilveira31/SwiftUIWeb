import SwiftUIWeb

/// The ways on from the hero: start, look at the components, or read the source. Start is the filled button, the other two
/// the same quieter one.
///
/// On a wide screen they sit in one row. On a narrow one the row would squeeze them (a button's label wrapping onto two lines),
/// so they take the first arrangement that fits: all three in a row, two in a row with the source under them, or one under
/// another. Each keeps its label on one line.
struct HeroActions: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) { startButton; componentsButton; sourceLink }
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) { startButton; componentsButton }
        sourceLink
      }
      VStack(alignment: .leading, spacing: 12) { startButton; componentsButton; sourceLink }
    }
  }

  @ViewBuilder
  private var startButton: some View {
    if let start = SiteLinks.page(.start, language) {
      SiteLinkButton(title: PurposeStrings.ctaStart(language), destination: start, isProminent: true)
    }
  }

  @ViewBuilder
  private var componentsButton: some View {
    if let components = SiteLinks.page(.components, language) {
      SiteLinkButton(title: PurposeStrings.ctaComponents(language), destination: components)
    }
  }

  @ViewBuilder
  private var sourceLink: some View {
    if let source = SiteLinks.repository {
      SiteLinkButton(title: ShellStrings.repositoryName, destination: source)
    }
  }
}

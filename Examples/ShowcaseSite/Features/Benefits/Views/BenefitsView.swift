import SwiftUIWeb

/// What the framework gives the people who use it.
struct BenefitsView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageScaffold(width: SiteLayout.wideWidth) {
      SiteHeading(text: BenefitsStrings.title(language), isPageTitle: true)
      SiteParagraph(text: BenefitsStrings.lead(language), isLead: true)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
        ForEach(BenefitsStrings.all(language), id: \.id) { benefit in BenefitCard(benefit: benefit) }
      }
    }
  }
}

import SwiftUIWeb

/// What the framework gives the people who use it.
struct BenefitsView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageScaffold {
      SitePageHeader(title: BenefitsStrings.title(language), lead: BenefitsStrings.lead(language))
      SiteCardGrid {
        ForEach(BenefitsStrings.all(language), id: \.id) { benefit in BenefitCard(benefit: benefit) }
      }
    }
  }
}

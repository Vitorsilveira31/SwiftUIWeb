import SwiftUIWeb

/// The two ways on from the hero: start, or look at the components; and the source.
struct HeroActions: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    HStack(spacing: 10) {
      if let start = SiteLinks.page(.start, language) {
        SiteLinkButton(title: PurposeStrings.ctaStart(language), destination: start, isProminent: true)
      }
      if let components = SiteLinks.page(.components, language) {
        SiteLinkButton(title: PurposeStrings.ctaComponents(language), destination: components)
      }
      if let source = SiteLinks.repository {
        Link(ShellStrings.repositoryName, destination: source).padding(.leading, 6)
      }
    }
  }
}

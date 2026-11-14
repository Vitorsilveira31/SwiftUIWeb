import SwiftUIWeb

/// Getting started: what to install, the four steps from an empty folder to a deployed app, and where to read more.
struct StartView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageScaffold {
      SiteHeading(text: StartStrings.title(language), isPageTitle: true)
      SiteParagraph(text: StartStrings.lead(language), isLead: true)
      PurposeSection(
        heading: StartStrings.requirementsHeading(language),
        items: StartStrings.requirements(language),
        symbol: "shippingbox"
      )
      SiteHeading(text: StartStrings.stepsHeading(language))
      ForEach(StartStrings.steps(language), id: \.id) { step in StartStepCard(step: step) }
      SiteHeading(text: StartStrings.nextHeading(language))
      VStack(alignment: .leading, spacing: 8) {
        ForEach(StartStrings.docLinks(language), id: \.path) { item in
          if let url = SiteLinks.documentation(item.path) { Link(item.title, destination: url) }
        }
      }
    }
  }
}

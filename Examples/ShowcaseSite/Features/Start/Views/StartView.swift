import SwiftUIWeb

/// Getting started: what to install, the four steps from an empty folder to a deployed app, and where to read more.
struct StartView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageScaffold {
      SitePageHeader(title: StartStrings.title(language), lead: StartStrings.lead(language))
      PurposeSection(
        heading: StartStrings.requirementsHeading(language),
        items: StartStrings.requirements(language),
        symbol: "shippingbox"
      )
      SiteSection(heading: StartStrings.stepsHeading(language)) {
        VStack(alignment: .leading, spacing: SiteLayout.gridSpacing) {
          ForEach(StartStrings.steps(language), id: \.id) { step in StartStepCard(step: step) }
        }
      }
      SiteSection(heading: StartStrings.nextHeading(language)) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(StartStrings.docLinks(language), id: \.path) { item in
            if let url = SiteLinks.documentation(item.path) { Link(item.title, destination: url) }
          }
        }
      }
    }
  }
}

import SwiftUIWeb

/// The top of a page: its title and the larger sentence that says what the page is for.
struct SitePageHeader: View {
  let title: String
  var lead: String?

  var body: some View {
    VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
      SiteHeading(text: title, isPageTitle: true)
      if let lead { SiteParagraph(text: lead, isLead: true) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

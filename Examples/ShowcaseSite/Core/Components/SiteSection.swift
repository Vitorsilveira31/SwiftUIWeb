import SwiftUIWeb

/// A section of a page: its heading and what the heading introduces, `blockSpacing` apart; the page puts its sections
/// `sectionSpacing` apart.
struct SiteSection<Content: View>: View {
  let heading: String
  let content: Content

  init(heading: String, @ViewBuilder content: () -> Content) {
    self.heading = heading
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
      SiteHeading(text: heading)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

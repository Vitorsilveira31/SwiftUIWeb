import SwiftUIWeb

/// A link drawn as a card: a document symbol, the title in the accent color and an arrow, so it reads as something to open
/// and not as a line of text. The whole card is the link.
struct SiteLinkCard: View {
  let title: String
  let destination: URL

  var body: some View {
    Link(destination: destination) {
      HStack(spacing: 10) {
        Image(systemName: "doc.text").accessibilityHidden(true)
        Text(title).fontWeight(.semibold)
        Spacer(minLength: 8)
        Image(systemName: "arrow.right").accessibilityHidden(true)
      }
      .foregroundStyle(SiteTheme.accent)
      .padding(SiteLayout.cardPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.primary.opacity(0.04))
      .clipShape(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius))
      .overlay(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius).stroke(Color.primary.opacity(0.12)))
    }
  }
}

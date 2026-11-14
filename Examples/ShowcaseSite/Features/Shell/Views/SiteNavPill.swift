import SwiftUIWeb

/// One page in the navigation row: a link to the page's address, so Back, a new tab and a copied link all work.
struct SiteNavPill: View {
  let page: SitePage
  let isSelected: Bool
  let language: SiteLanguage

  var body: some View {
    if let destination = SiteLinks.page(page, language) {
      Link(destination: destination) {
        Text(ShellStrings.tab(page, language))
          .font(.callout)
          .fontWeight(isSelected ? .semibold : .regular)
          .foregroundStyle(isSelected ? Color.primary : Color.secondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(isSelected ? Color.primary.opacity(0.1) : Color.clear)
          .clipShape(Capsule())
      }
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
  }
}

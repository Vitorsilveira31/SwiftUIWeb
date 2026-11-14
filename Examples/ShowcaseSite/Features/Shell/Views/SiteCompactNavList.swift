import SwiftUIWeb

/// The pages as a list of links, under a narrow header. Each is a link to the page's address (see `SiteNavPill`).
struct SiteCompactNavList: View {
  let viewModel: SiteViewModel
  private static let rowWidth: CGFloat = 240

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(SitePage.allCases, id: \.self) { page in
        if let destination = SiteLinks.page(page, viewModel.language) {
          let isSelected = page == viewModel.page
          Link(destination: destination) {
            Label(ShellStrings.tab(page, viewModel.language), systemImage: page.symbol)
              .fontWeight(isSelected ? .semibold : .regular)
              .foregroundStyle(isSelected ? Color.primary : Color.secondary)
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
              // A link is as wide as what it holds, so a highlight is as wide as its label. A common minimum width gives every
              // page the same highlight, the longest label included.
              .frame(minWidth: Self.rowWidth, maxWidth: .infinity, alignment: .leading)
              .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
              .clipShape(RoundedRectangle(cornerRadius: 10))
          }
          .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
      }
    }
    .padding(.top, 8)
  }
}

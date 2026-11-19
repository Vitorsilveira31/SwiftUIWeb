import SwiftUIWeb

/// The pages as a list of links, under a narrow header. Each is a link to the page's address (see `SiteNavPill`).
struct SiteCompactNavList: View {
  let viewModel: SiteViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(SitePage.allCases, id: \.self) { page in
        if let destination = SiteLinks.page(page, viewModel.language) {
          let isSelected = page == viewModel.page
          Link(destination: destination) {
            // Every row is as wide as the header, so the highlight runs from edge to edge of the column whatever the label,
            // the way a row of a list is selected. The spacer is what makes the link take the width (as in `SiteLinkCard`).
            HStack(spacing: 0) {
              Label(ShellStrings.tab(page, viewModel.language), systemImage: page.symbol)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }
          .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 8)
  }
}

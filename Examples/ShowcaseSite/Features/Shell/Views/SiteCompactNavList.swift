import SwiftUIWeb

/// The pages as a list of links, under a narrow header. Each is a link to the page's address (see `SiteNavPill`).
struct SiteCompactNavList: View {
  let viewModel: SiteViewModel
  /// The label's minimum width: with the 12pt of padding on each side, every row is 240pt wide.
  private static let labelWidth: CGFloat = 216

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(SitePage.allCases, id: \.self) { page in
        if let destination = SiteLinks.page(page, viewModel.language) {
          let isSelected = page == viewModel.page
          Link(destination: destination) {
            // A link is as wide as what it holds, so a highlight is as wide as its label. The label has a common minimum width,
            // which gives every page the same highlight, the longest label included. The padding is on the stack around it:
            // a padding and a frame on one view share one box, and one of the two is lost.
            HStack(spacing: 0) {
              Label(ShellStrings.tab(page, viewModel.language), systemImage: page.symbol)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(minWidth: Self.labelWidth, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

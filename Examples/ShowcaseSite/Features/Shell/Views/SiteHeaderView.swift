import SwiftUIWeb

/// The site's header: the brand, the pages and the reader's preferences. When the row of pills does not fit, the pages collapse
/// into one button beside the preferences, that opens the list of pages under the header. It sits in the pages' column
/// (`SitePageFrame`), so the brand lines up with every page's title.
struct SiteHeaderView: View {
  let viewModel: SiteViewModel
  @State private var isNavOpen = false

  var body: some View {
    SitePageFrame {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) {
          SiteBrandView(language: viewModel.language)
          Spacer(minLength: 8)
          SiteNavView(viewModel: viewModel)
          Spacer(minLength: 8)
          SiteSettingsMenu(viewModel: viewModel)
        }
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 10) {
            SiteBrandView(language: viewModel.language)
            Spacer(minLength: 8)
            SiteSettingsMenu(viewModel: viewModel)
            SiteCompactNavMenu(isOpen: $isNavOpen)
          }
          if isNavOpen { SiteCompactNavList(viewModel: viewModel) }
        }
      }
    }
    .padding(.vertical, 10)
    // Choosing a page closes the list.
    .onChange(of: viewModel.page) { _ in isNavOpen = false }
  }
}

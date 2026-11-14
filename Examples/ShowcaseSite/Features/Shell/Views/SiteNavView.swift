import SwiftUIWeb

/// The pages as a row of pills; the page shown is filled.
struct SiteNavView: View {
  let viewModel: SiteViewModel

  var body: some View {
    HStack(spacing: 4) {
      ForEach(SitePage.allCases, id: \.self) { page in
        SiteNavPill(page: page, isSelected: page == viewModel.page, language: viewModel.language)
      }
    }
  }
}

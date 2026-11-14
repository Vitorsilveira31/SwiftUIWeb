import SwiftUIWeb

/// The component list beside the entry shown. The title stays in place and the list and the entry each scroll on their own,
/// so choosing a component far down the list does not scroll the entry away.
struct ComponentsWideLayout: View {
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: SiteLayout.sectionSpacing) {
      SiteHeading(text: ComponentsStrings.title(language), isPageTitle: true)
      HStack(alignment: .top, spacing: 28) {
        ScrollView { ComponentsListView(viewModel: viewModel).padding(.bottom, SiteLayout.sectionSpacing) }
          .frame(width: 220)
        ScrollView { ComponentDetailView(viewModel: viewModel).padding(.bottom, SiteLayout.sectionSpacing) }
          .frame(maxWidth: .infinity)
      }
      .frame(maxHeight: .infinity)
    }
    .frame(maxWidth: SiteLayout.wideWidth, maxHeight: .infinity, alignment: .topLeading)
    .padding(.horizontal, SiteLayout.gutter)
    .padding(.top, SiteLayout.sectionSpacing)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

import SwiftUIWeb

/// The component list beside the entry shown. The title stays in place and the list and the entry each scroll on their own,
/// so choosing a component far down the list does not scroll the entry away. The page sits in the same column as every other
/// (`SitePageFrame`), with its title at the same height.
struct ComponentsWideLayout: View {
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageFrame {
      VStack(alignment: .leading, spacing: SiteLayout.sectionSpacing) {
        SitePageHeader(title: ComponentsStrings.title(language), lead: ComponentsStrings.lead(language))
        HStack(alignment: .top, spacing: SiteLayout.sectionSpacing) {
          ScrollView { ComponentsListView(viewModel: viewModel).padding(.bottom, SiteLayout.pageInset) }
            .frame(width: 220)
          ScrollView { ComponentDetailView(viewModel: viewModel).padding(.bottom, SiteLayout.pageInset) }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .padding(.top, SiteLayout.pageInset)
  }
}

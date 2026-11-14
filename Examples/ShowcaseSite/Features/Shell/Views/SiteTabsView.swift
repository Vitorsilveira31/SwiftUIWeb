import SwiftUIWeb

/// The pages of the site as tabs. Each page gives the browser its address, title and description, so a link, a reload and
/// the Back button come back to it; the address is read again at the start (see `SiteRootView`). The tab bar itself is
/// hidden: the header (`SiteHeaderView`) is the navigation, and it selects the page through the same binding.
struct SiteTabsView: View {
  @Binding var page: SitePage
  let language: SiteLanguage
  let components: ComponentsViewModel
  let performance: PerformanceViewModel

  var body: some View {
    TabView(selection: $page) {
      PurposeView()
        .toolbar(.hidden, for: .tabBar)
        .modifier(metadata(.purpose))
        .tabItem { Label(ShellStrings.tab(.purpose, language), systemImage: SitePage.purpose.symbol) }.tag(SitePage.purpose)
      StartView()
        .toolbar(.hidden, for: .tabBar)
        .modifier(metadata(.start))
        .tabItem { Label(ShellStrings.tab(.start, language), systemImage: SitePage.start.symbol) }.tag(SitePage.start)
      BenefitsView()
        .toolbar(.hidden, for: .tabBar)
        .modifier(metadata(.benefits))
        .tabItem { Label(ShellStrings.tab(.benefits, language), systemImage: SitePage.benefits.symbol) }.tag(SitePage.benefits)
      PerformanceView(viewModel: performance)
        .toolbar(.hidden, for: .tabBar)
        .modifier(metadata(.performance))
        .tabItem { Label(ShellStrings.tab(.performance, language), systemImage: SitePage.performance.symbol) }.tag(SitePage.performance)
      ComponentsView(viewModel: components)
        .toolbar(.hidden, for: .tabBar)
        .modifier(metadata(.components))
        .tabItem { Label(ShellStrings.tab(.components, language), systemImage: SitePage.components.symbol) }.tag(SitePage.components)
    }
  }

  private func metadata(_ page: SitePage) -> SitePageMetadata {
    let entry = page == .components ? components.selected : nil
    return SitePageMetadata(
      route: SiteRoute(language: language, page: page, entry: entry?.id),
      entryName: entry?.name,
      language: language
    )
  }
}

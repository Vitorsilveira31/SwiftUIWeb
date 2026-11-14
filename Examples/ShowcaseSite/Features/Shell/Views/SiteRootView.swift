import SwiftUIWeb

/// The site: header on top, the pages below, in the language and appearance the reader chose.
struct SiteRootView: View {
  @State private var viewModel: SiteViewModel
  @State private var components: ComponentsViewModel
  @State private var performance: PerformanceViewModel

  init(dependencies: SiteDependencies) {
    _viewModel = State(wrappedValue: SiteViewModel(dependencies: dependencies))
    let componentsModel = ComponentsViewModel(load: dependencies.loadCatalog, search: dependencies.searchCatalog)
    _components = State(wrappedValue: componentsModel)
    _performance = State(wrappedValue: PerformanceViewModel(load: dependencies.loadPerformance))
  }

  var body: some View {
    VStack(spacing: 0) {
      SiteHeaderView(viewModel: viewModel)
      Divider()
      SiteTabsView(page: $viewModel.page, language: viewModel.language, components: components, performance: performance)
    }
    .environment(\.siteLanguage, viewModel.language)
    .preferredColorScheme(viewModel.colorScheme)
    .onOpenURL { open($0) }
  }

  /// A link or a reload at an address of the site: put the page, the language and the entry where the address says.
  private func open(_ url: URL) {
    guard let route = SiteRoute.parse(path: url.path) else { return }
    viewModel.open(route)
    components.open(entry: route.entry)
  }
}

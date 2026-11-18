import SwiftUIWeb

/// The entry shown under a menu that picks it, on a page that scrolls as a whole.
struct ComponentsNarrowLayout: View {
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageScaffold {
      SitePageHeader(title: ComponentsStrings.title(language), lead: ComponentsStrings.lead(language))
      ComponentsCompactPicker(viewModel: viewModel)
      ComponentDetailView(viewModel: viewModel)
    }
  }
}

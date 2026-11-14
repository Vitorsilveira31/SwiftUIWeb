import SwiftUIWeb

/// The search field and the component list, grouped by category.
struct ComponentsListView: View {
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      TextField(ComponentsStrings.searchPrompt(language), text: Binding(get: { viewModel.query }, set: { viewModel.query = $0 }))
        .textFieldStyle(.roundedBorder)
      ForEach(viewModel.groups(language), id: \.category) { group in
        ComponentsListGroup(group: group, viewModel: viewModel)
      }
      if viewModel.groups(language).isEmpty {
        Text(ComponentsStrings.noResults(language)).foregroundStyle(.secondary)
      }
    }
  }
}

import SwiftUIWeb

/// One category of the component list: its name, then its entries.
struct ComponentsListGroup: View {
  let group: ComponentsGroupVO
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(ComponentsStrings.category(group.category, language))
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
      ForEach(group.recipes, id: \.id) { recipe in
        ComponentsListRow(recipe: recipe, viewModel: viewModel)
      }
    }
  }
}

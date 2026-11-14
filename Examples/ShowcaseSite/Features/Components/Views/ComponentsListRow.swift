import SwiftUIWeb

/// One entry of the component list; the one shown is highlighted.
struct ComponentsListRow: View {
  let recipe: CatalogRecipe
  let viewModel: ComponentsViewModel

  var body: some View {
    Button { viewModel.select(recipe.id) } label: {
      Text(recipe.name)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var isSelected: Bool { recipe.id == viewModel.selectedID }
}

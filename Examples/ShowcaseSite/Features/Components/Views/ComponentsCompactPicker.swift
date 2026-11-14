import SwiftUIWeb

/// On a narrow screen the list does not come first: one native menu names the entry shown and opens the whole catalog, so the
/// entry itself is on screen as soon as the page is.
struct ComponentsCompactPicker: View {
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    Picker(
      ComponentsStrings.title(language),
      selection: Binding(get: { viewModel.selectedID ?? "" }, set: { viewModel.select($0) })
    ) {
      ForEach(viewModel.allGroups(), id: \.category) { group in
        ForEach(group.recipes, id: \.id) { recipe in Text(recipe.name).tag(recipe.id) }
      }
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

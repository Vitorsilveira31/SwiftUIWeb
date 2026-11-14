import SwiftUIWeb

/// On a narrow screen the list does not come first: one native menu names the entry shown and opens the whole catalog, so the
/// entry itself is on screen as soon as the page is.
struct ComponentsCompactPicker: View {
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    // A menu picker with no label is a bare piece of text. With an empty title it is a field, with the border and the
    // indicator that show it opens a menu; the screen reader still hears what it chooses.
    Picker(
      "",
      selection: Binding(get: { viewModel.selectedID ?? "" }, set: { viewModel.select($0) })
    ) {
      ForEach(viewModel.allGroups(), id: \.category) { group in
        ForEach(group.recipes, id: \.id) { recipe in Text(recipe.name).tag(recipe.id) }
      }
    }
    .pickerStyle(.menu)
    .accessibilityLabel(ComponentsStrings.title(language))
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

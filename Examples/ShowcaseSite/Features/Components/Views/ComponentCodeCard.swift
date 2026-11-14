import SwiftUIWeb

/// The code of the component as it is now, written from the same knob values the live view uses.
struct ComponentCodeCard: View {
  let recipe: CatalogRecipe
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(ComponentsStrings.codeHeading(language)).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
      SiteCodeBlock(code: recipe.code(viewModel.values))
    }
  }
}

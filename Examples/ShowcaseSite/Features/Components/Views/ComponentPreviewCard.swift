import SwiftUIWeb

/// The live component, in a surface of its own.
struct ComponentPreviewCard: View {
  let recipe: CatalogRecipe
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SiteCard {
      Text(ComponentsStrings.previewHeading(language)).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
      recipe.preview(viewModel.values)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
    }
  }
}

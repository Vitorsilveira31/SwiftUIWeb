import SwiftUIWeb

/// The entry that is shown: what it is, the live component, its knobs and its code.
struct ComponentDetailView: View {
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    if let recipe = viewModel.selected {
      VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
        SiteHeading(text: recipe.name)
        SiteParagraph(text: recipe.summary.resolved(language))
        ComponentPreviewCard(recipe: recipe, viewModel: viewModel)
        ComponentKnobsCard(recipe: recipe, viewModel: viewModel)
        ComponentCodeCard(recipe: recipe, viewModel: viewModel)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      SiteParagraph(text: ComponentsStrings.pickPrompt(language))
    }
  }
}

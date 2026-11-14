import SwiftUIWeb

/// The knobs of the component shown, and the button that puts them back.
struct ComponentKnobsCard: View {
  let recipe: CatalogRecipe
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SiteCard {
      Text(ComponentsStrings.knobsHeading(language)).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
      ForEach(recipe.knobs, id: \.id) { knob in ComponentKnobRow(knob: knob, viewModel: viewModel) }
      Button(ComponentsStrings.reset(language)) { viewModel.resetKnobs() }.buttonStyle(.bordered)
    }
  }
}

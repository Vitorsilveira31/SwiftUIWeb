import SwiftUIWeb

/// Language and appearance in one menu: two preferences that are set once, so they take one control, not two.
///
/// The items are plain buttons under a small heading, not `Section`s: a `Section` inside a `Menu` is drawn as a form section, with
/// separators and rows of its own. Every item has the same shape, a symbol and a name (a check for the one in use, an empty circle
/// for the others), so the names line up.
///
/// The language comes from the environment, not from the view model read inside the menu's closures: a menu builds its items
/// when it opens, and the environment is what reaches it when the language changes from an address (`/pt/purpose` on a first
/// visit), not only from the menu itself.
struct SiteSettingsMenu: View {
  let viewModel: SiteViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    let appearance = viewModel.appearance
    Menu {
      SiteMenuHeading(text: ShellStrings.languageLabel(language))
      ForEach(SiteLanguage.allCases, id: \.self) { option in
        Button { viewModel.select(language: option) } label: {
          Label(option.name, systemImage: option == language ? "checkmark.circle" : "circle")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Divider()
      SiteMenuHeading(text: ShellStrings.appearanceLabel(language))
      ForEach(SiteAppearance.allCases, id: \.self) { option in
        Button { viewModel.select(appearance: option) } label: {
          Label(ShellStrings.appearance(option, language), systemImage: option == appearance ? "checkmark.circle" : "circle")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "globe")
        Text(language.rawValue.uppercased()).font(.callout).fontWeight(.semibold)
      }
    }
    .id(language)
    .accessibilityLabel(ShellStrings.settingsLabel(language))
  }
}

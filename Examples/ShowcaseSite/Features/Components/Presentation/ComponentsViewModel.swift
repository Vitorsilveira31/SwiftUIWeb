import SwiftUIWeb

/// The components page's state: the search, the entry shown and the knob values of that entry.
@MainActor @Observable
final class ComponentsViewModel {
  var query = ""
  private(set) var selectedID: String?
  private(set) var values = CatalogKnobValues(defaults: [])
  private let recipes: [CatalogRecipe]
  private let search: any SearchComponentCatalogUseCase

  init(load: any LoadComponentCatalogUseCase, search: any SearchComponentCatalogUseCase) {
    recipes = load.execute()
    self.search = search
    if let first = recipes.first { select(first.id) }
  }

  var selected: CatalogRecipe? { recipes.first { $0.id == selectedID } }

  /// The entries matching the search, sorted into their categories in the order of `CatalogCategory`.
  func groups(_ language: SiteLanguage) -> [ComponentsGroupVO] {
    grouped(search.execute(recipes, query: query, language: language))
  }

  /// Every entry in its category, whatever the search: the list of a screen with no search field must not keep the filter of one
  /// that had it (a visitor who filtered on a wide screen and then narrowed the window).
  func allGroups() -> [ComponentsGroupVO] {
    grouped(recipes)
  }

  private func grouped(_ matches: [CatalogRecipe]) -> [ComponentsGroupVO] {
    CatalogCategory.allCases.compactMap { category in
      let inCategory = matches.filter { $0.category == category }
      return inCategory.isEmpty ? nil : ComponentsGroupVO(category: category, recipes: inCategory)
    }
  }

  /// Shows another entry, with every knob back at its default.
  func select(_ id: String?) {
    selectedID = id
    values = CatalogKnobValues(defaults: selected?.knobs ?? [])
  }

  /// Shows the entry an address names; an unknown or missing one leaves the entry that is shown.
  func open(entry id: String?) {
    guard let id, recipes.contains(where: { $0.id == id }), id != selectedID else { return }
    select(id)
  }

  func resetKnobs() { values = CatalogKnobValues(defaults: selected?.knobs ?? []) }

  func set(_ id: String, bool value: Bool) { values.set(id, bool: value) }
  func set(_ id: String, number value: Double) { values.set(id, number: value) }
  func set(_ id: String, text value: String) { values.set(id, text: value) }
  func set(_ id: String, choiceIndex value: Int) { values.set(id, choiceIndex: value) }
}

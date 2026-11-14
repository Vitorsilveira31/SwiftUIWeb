import Foundation

protocol SearchComponentCatalogUseCase {
  func execute(_ recipes: [CatalogRecipe], query: String, language: SiteLanguage) -> [CatalogRecipe]
}

/// Keeps the entries whose name or summary, in the language shown, contains what was typed.
struct DefaultSearchComponentCatalogUseCase: SearchComponentCatalogUseCase {
  func execute(_ recipes: [CatalogRecipe], query: String, language: SiteLanguage) -> [CatalogRecipe] {
    let needle = query.lowercased()
    if needle.isEmpty { return recipes }
    return recipes.filter {
      $0.name.lowercased().contains(needle) || $0.summary.resolved(language).lowercased().contains(needle)
    }
  }
}

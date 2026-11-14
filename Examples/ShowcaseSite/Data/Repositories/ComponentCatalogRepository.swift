/// Where the catalog's entries come from.
protocol ComponentCatalogRepository {
  func recipes() -> [CatalogRecipe]
}

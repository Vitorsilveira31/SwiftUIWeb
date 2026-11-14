protocol LoadComponentCatalogUseCase { func execute() -> [CatalogRecipe] }

struct DefaultLoadComponentCatalogUseCase: LoadComponentCatalogUseCase {
  let repository: any ComponentCatalogRepository

  func execute() -> [CatalogRecipe] { repository.recipes() }
}

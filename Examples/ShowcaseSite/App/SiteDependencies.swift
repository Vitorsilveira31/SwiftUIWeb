import SwiftUIWeb

/// What the site needs from the outside, in one place: a test builds it with doubles, the app with `live`.
struct SiteDependencies {
  let readPreferences: any ReadSitePreferencesUseCase
  let chooseLanguage: any ChooseSiteLanguageUseCase
  let chooseAppearance: any ChooseSiteAppearanceUseCase
  let loadCatalog: any LoadComponentCatalogUseCase
  let searchCatalog: any SearchComponentCatalogUseCase
  let loadPerformance: any LoadPerformanceResultsUseCase

  static var live: SiteDependencies {
    let preferences = LiveSitePreferencesRepository()
    return SiteDependencies(
      readPreferences: DefaultReadSitePreferencesUseCase(
        repository: preferences,
        preferredLanguages: { Locale.preferredLanguages }
      ),
      chooseLanguage: DefaultChooseSiteLanguageUseCase(repository: preferences),
      chooseAppearance: DefaultChooseSiteAppearanceUseCase(repository: preferences),
      loadCatalog: DefaultLoadComponentCatalogUseCase(repository: LiveComponentCatalogRepository()),
      searchCatalog: DefaultSearchComponentCatalogUseCase(),
      loadPerformance: DefaultLoadPerformanceResultsUseCase(repository: LivePerformanceResultsRepository())
    )
  }
}

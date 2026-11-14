import Testing
@testable import ShowcaseSite

@MainActor
struct SitePreferencesTests {
  private func dependencies(_ repository: InMemorySitePreferencesRepository, browser: [String] = []) -> SiteDependencies {
    SiteDependencies(
      readPreferences: DefaultReadSitePreferencesUseCase(repository: repository, preferredLanguages: { browser }),
      chooseLanguage: DefaultChooseSiteLanguageUseCase(repository: repository),
      chooseAppearance: DefaultChooseSiteAppearanceUseCase(repository: repository),
      loadCatalog: DefaultLoadComponentCatalogUseCase(repository: LiveComponentCatalogRepository()),
      searchCatalog: DefaultSearchComponentCatalogUseCase(),
      loadPerformance: DefaultLoadPerformanceResultsUseCase(repository: LivePerformanceResultsRepository())
    )
  }

  @Test func aFirstVisitStartsFromTheBrowserLanguageAndTheSystemAppearance() {
    let model = SiteViewModel(dependencies: dependencies(InMemorySitePreferencesRepository(), browser: ["pt-BR"]))
    #expect(model.language == .pt)
    #expect(model.appearance == .system)
    #expect(model.colorScheme == nil)
  }

  @Test func whatWasChosenBeforeWinsOverTheBrowser() {
    let repository = InMemorySitePreferencesRepository(language: .en, appearance: .dark)
    let model = SiteViewModel(dependencies: dependencies(repository, browser: ["pt-BR"]))
    #expect(model.language == .en)
    #expect(model.colorScheme == .dark)
  }

  @Test func choosingStoresTheChoice() {
    let repository = InMemorySitePreferencesRepository()
    let model = SiteViewModel(dependencies: dependencies(repository))
    model.select(language: .pt)
    model.select(appearance: .light)
    #expect(repository.language == .pt)
    #expect(repository.appearance == .light)
    #expect(model.language == .pt)
    #expect(model.colorScheme == .light)
  }

  @Test func openingARouteShowsItsPageAndLanguageWithoutRememberingTheLanguage() {
    let repository = InMemorySitePreferencesRepository(language: .en)
    let model = SiteViewModel(dependencies: dependencies(repository))
    model.open(SiteRoute(language: .pt, page: .benefits, entry: nil))
    #expect(model.page == .benefits)
    #expect(model.language == .pt)
    #expect(repository.language == .en)
  }

  @Test func goingBackKeepsTheLanguageTheReaderHasNow() {
    let model = SiteViewModel(dependencies: dependencies(InMemorySitePreferencesRepository(language: .en)))
    model.open(SiteRoute(language: .en, page: .purpose, entry: nil))
    model.select(language: .pt)
    model.open(SiteRoute(language: .en, page: .benefits, entry: nil))
    #expect(model.page == .benefits)
    #expect(model.language == .pt)
  }

  @Test func aRouteWithoutALanguageKeepsTheLanguageShown() {
    let model = SiteViewModel(dependencies: dependencies(InMemorySitePreferencesRepository(language: .pt)))
    model.open(SiteRoute(language: nil, page: .purpose, entry: nil))
    #expect(model.language == .pt)
    #expect(model.page == .purpose)
  }

  @Test func theSiteOpensOnWhatItIsFor() {
    #expect(SiteViewModel(dependencies: dependencies(InMemorySitePreferencesRepository())).page == .purpose)
  }
}

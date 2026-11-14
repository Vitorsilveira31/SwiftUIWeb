/// Where the reader's choices are kept between visits.
protocol SitePreferencesRepository {
  func storedLanguage() -> SiteLanguage?
  func storedAppearance() -> SiteAppearance?
  func store(language: SiteLanguage)
  func store(appearance: SiteAppearance)
}

@testable import ShowcaseSite

/// A repository that keeps the choices in memory, so a test sees what was stored.
final class InMemorySitePreferencesRepository: SitePreferencesRepository {
  var language: SiteLanguage?
  var appearance: SiteAppearance?

  init(language: SiteLanguage? = nil, appearance: SiteAppearance? = nil) {
    self.language = language
    self.appearance = appearance
  }

  func storedLanguage() -> SiteLanguage? { language }
  func storedAppearance() -> SiteAppearance? { appearance }
  func store(language: SiteLanguage) { self.language = language }
  func store(appearance: SiteAppearance) { self.appearance = appearance }
}

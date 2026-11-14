import SwiftUIWeb

/// The browser's local storage, through `UserDefaults`.
struct LiveSitePreferencesRepository: SitePreferencesRepository {
  private let languageKey = "site.language"
  private let appearanceKey = "site.appearance"

  func storedLanguage() -> SiteLanguage? {
    UserDefaults.standard.string(forKey: languageKey).flatMap { SiteLanguage(rawValue: $0) }
  }

  func storedAppearance() -> SiteAppearance? {
    UserDefaults.standard.string(forKey: appearanceKey).flatMap { SiteAppearance(rawValue: $0) }
  }

  func store(language: SiteLanguage) {
    UserDefaults.standard.set(language.rawValue, forKey: languageKey)
  }

  func store(appearance: SiteAppearance) {
    UserDefaults.standard.set(appearance.rawValue, forKey: appearanceKey)
  }
}

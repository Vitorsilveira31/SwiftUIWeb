protocol ReadSitePreferencesUseCase { func execute() -> SitePreferencesVO }

/// What the reader chose last time; first visits start from the browser's language and the system appearance.
struct DefaultReadSitePreferencesUseCase: ReadSitePreferencesUseCase {
  let repository: any SitePreferencesRepository
  let preferredLanguages: () -> [String]

  func execute() -> SitePreferencesVO {
    SitePreferencesVO(
      language: repository.storedLanguage() ?? SiteLanguage.detect(preferred: preferredLanguages()),
      appearance: repository.storedAppearance() ?? .system
    )
  }
}

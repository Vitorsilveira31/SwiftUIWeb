protocol ChooseSiteLanguageUseCase { func execute(_ language: SiteLanguage) }

struct DefaultChooseSiteLanguageUseCase: ChooseSiteLanguageUseCase {
  let repository: any SitePreferencesRepository

  func execute(_ language: SiteLanguage) { repository.store(language: language) }
}

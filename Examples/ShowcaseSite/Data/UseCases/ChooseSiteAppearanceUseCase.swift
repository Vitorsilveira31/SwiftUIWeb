protocol ChooseSiteAppearanceUseCase { func execute(_ appearance: SiteAppearance) }

struct DefaultChooseSiteAppearanceUseCase: ChooseSiteAppearanceUseCase {
  let repository: any SitePreferencesRepository

  func execute(_ appearance: SiteAppearance) { repository.store(appearance: appearance) }
}

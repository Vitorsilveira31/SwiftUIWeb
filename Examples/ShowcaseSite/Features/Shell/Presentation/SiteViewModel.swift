import SwiftUIWeb

/// The shell's state: the page shown and the reader's language and appearance.
@MainActor @Observable
final class SiteViewModel {
  var page: SitePage = .purpose
  private(set) var language: SiteLanguage
  private(set) var appearance: SiteAppearance
  private var hasOpenedAddress = false
  private let chooseLanguage: any ChooseSiteLanguageUseCase
  private let chooseAppearance: any ChooseSiteAppearanceUseCase

  init(dependencies: SiteDependencies) {
    let preferences = dependencies.readPreferences.execute()
    language = preferences.language
    appearance = preferences.appearance
    chooseLanguage = dependencies.chooseLanguage
    chooseAppearance = dependencies.chooseAppearance
  }

  /// The scheme the site forces, or nil to follow the system.
  var colorScheme: ColorScheme? {
    switch appearance {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  /// Shows the page an address names. A link opened first (a shared address, a reload) sets the language it names and does
  /// not remember it: the reader's own choice stays what it was for the next visit. Back and Forward show the page of an
  /// older address in the language the reader has now, so choosing a language is never undone by going back.
  func open(_ route: SiteRoute) {
    if !hasOpenedAddress, let named = route.language { language = named }
    hasOpenedAddress = true
    page = route.page
  }

  func select(language newLanguage: SiteLanguage) {
    language = newLanguage
    chooseLanguage.execute(newLanguage)
  }

  func select(appearance newAppearance: SiteAppearance) {
    appearance = newAppearance
    chooseAppearance.execute(newAppearance)
  }
}

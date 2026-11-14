/// The shell's own words: the site name, the tabs and the preference controls.
enum ShellStrings {
  static let siteName = "SwiftUIWeb"

  static func tagline(_ language: SiteLanguage) -> String {
    language.pick(pt: "SwiftUI na web", en: "SwiftUI on the web")
  }

  static func tab(_ page: SitePage, _ language: SiteLanguage) -> String {
    switch page {
    case .purpose: return language.pick(pt: "Propósito", en: "Purpose")
    case .start: return language.pick(pt: "Começar", en: "Get started")
    case .benefits: return language.pick(pt: "Benefícios", en: "Benefits")
    case .performance: return language.pick(pt: "Desempenho", en: "Performance")
    case .components: return language.pick(pt: "Componentes", en: "Components")
    case .animations: return language.pick(pt: "Animações", en: "Animations")
    }
  }

  static func menuLabel(_ language: SiteLanguage) -> String {
    language.pick(pt: "Menu", en: "Menu")
  }

  static func settingsLabel(_ language: SiteLanguage) -> String {
    language.pick(pt: "Idioma e aparência", en: "Language and appearance")
  }

  static let repositoryName = "GitHub"

  static func appearance(_ appearance: SiteAppearance, _ language: SiteLanguage) -> String {
    switch appearance {
    case .system: return language.pick(pt: "Automático", en: "Automatic")
    case .light: return language.pick(pt: "Claro", en: "Light")
    case .dark: return language.pick(pt: "Escuro", en: "Dark")
    }
  }

  /// The title the browser tab shows: the page, the entry when there is one, then the site.
  static func documentTitle(page: SitePage, entry: String?, _ language: SiteLanguage) -> String {
    if let entry { return "\(entry) · \(tab(page, language)) · \(siteName)" }
    return "\(tab(page, language)) · \(siteName)"
  }

  static func description(_ language: SiteLanguage) -> String {
    language.pick(
      pt: "SwiftUIWeb: o SwiftUI na web. Para que serve, os benefícios e um catálogo de componentes que você muda ao vivo.",
      en: "SwiftUIWeb: SwiftUI on the web. What it is for, its benefits and a catalog of components you can change live."
    )
  }

  static func languageLabel(_ language: SiteLanguage) -> String {
    language.pick(pt: "Idioma", en: "Language")
  }

  static func appearanceLabel(_ language: SiteLanguage) -> String {
    language.pick(pt: "Aparência", en: "Appearance")
  }
}

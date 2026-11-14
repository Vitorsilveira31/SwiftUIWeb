import SwiftUIWeb

private struct SiteLanguageKey: EnvironmentKey {
  static let defaultValue = SiteLanguage.en
}

extension EnvironmentValues {
  var siteLanguage: SiteLanguage {
    get { self[SiteLanguageKey.self] }
    set { self[SiteLanguageKey.self] = newValue }
  }
}

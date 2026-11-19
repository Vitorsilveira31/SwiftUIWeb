import SwiftUIWeb

/// The addresses outside the site that its pages point to.
enum SiteLinks {
  static let repository = URL(string: "https://github.com/Vitorsilveira31/SwiftUIWeb")

  /// The latest release, the version the getting-started manifest asks for. Update it with each release.
  static let release = "0.1.11"

  /// The address of a page of the site, in a language. A link to it is taken by the browser host and shown through
  /// `onOpenURL` without reloading the page, and it is a real link: it opens in a new tab, and Back returns to the page before.
  static func page(_ page: SitePage, _ language: SiteLanguage) -> URL? {
    URL(string: SiteRoute(language: language, page: page, entry: nil).path)
  }

  /// A file of the repository's documentation.
  static func documentation(_ path: String) -> URL? {
    URL(string: "https://github.com/Vitorsilveira31/SwiftUIWeb/blob/main/\(path)")
  }
}

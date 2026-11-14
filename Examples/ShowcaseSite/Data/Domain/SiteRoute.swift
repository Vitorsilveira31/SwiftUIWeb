/// An address of the site: `/pt/components/slider` is the Portuguese site, the Components page, the Slider entry.
struct SiteRoute: Equatable {
  /// The language the address names; nil for an address written without one (`/components`).
  var language: SiteLanguage?
  var page: SitePage
  /// The catalog entry, on the Components page only.
  var entry: String?

  /// The path segments of the address, in order.
  var segments: [String] {
    var parts: [String] = []
    if let language { parts.append(language.rawValue) }
    parts.append(page.rawValue)
    if page == .components, let entry { parts.append(entry) }
    return parts
  }

  /// The address these segments make, with its leading slash: `/pt/components/slider`.
  var path: String { "/" + segments.joined(separator: "/") }

  /// The route an address names, or nil when it names no page of the site. The language comes first and may be left out.
  static func parse(path: String) -> SiteRoute? {
    var parts = path.split(separator: "/").map(String.init)
    var language: SiteLanguage?
    if let first = parts.first, let named = SiteLanguage(rawValue: first) {
      language = named
      parts.removeFirst()
    }
    // An address that names only a language (`/pt`) opens that language's first page rather than being ignored.
    if parts.isEmpty { return language.map { SiteRoute(language: $0, page: .purpose, entry: nil) } }
    guard let slug = parts.first, let page = SitePage(rawValue: slug) else { return nil }
    return SiteRoute(language: language, page: page, entry: page == .components ? parts.dropFirst().first : nil)
  }
}

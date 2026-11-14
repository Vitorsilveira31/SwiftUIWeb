/// The two languages of the site. Content is written once per language, next to each other, so a change to one is seen
/// beside the other.
enum SiteLanguage: String, CaseIterable, Hashable {
  case pt
  case en

  /// A language is named in itself, whatever language the page is in.
  var name: String {
    switch self {
    case .pt: return "Português"
    case .en: return "English"
    }
  }

  func pick(pt portuguese: String, en english: String) -> String {
    self == .pt ? portuguese : english
  }

  /// The language of the browser's first preferred language; English when it is neither.
  static func detect(preferred: [String]) -> SiteLanguage {
    guard let first = preferred.first else { return .en }
    return first.lowercased().hasPrefix("pt") ? .pt : .en
  }
}

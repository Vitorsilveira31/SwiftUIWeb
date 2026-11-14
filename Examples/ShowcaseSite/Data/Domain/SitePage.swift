/// The pages of the site, in the order of the navigation.
enum SitePage: String, CaseIterable, Hashable {
  case purpose
  case start
  case benefits
  case performance
  case components

  /// The SF Symbol the page has in the compact navigation menu.
  var symbol: String {
    switch self {
    case .purpose: return "sparkles"
    case .start: return "play.circle"
    case .benefits: return "star"
    case .performance: return "gauge.with.dots.needle.67percent"
    case .components: return "square.grid.2x2"
    }
  }
}

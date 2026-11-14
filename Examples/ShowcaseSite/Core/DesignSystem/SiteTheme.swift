import SwiftUIWeb

/// The colors the site adds to the system's: one accent (Swift's orange) and the gradient made from it. Everything else is
/// the system palette, so light, dark and the contrast settings keep working.
enum SiteTheme {
  static let accent = Color(red: 0.94, green: 0.32, blue: 0.19)
  static let accentSoft = Color(red: 1.0, green: 0.55, blue: 0.2)

  /// The brand mark and the words that carry the page's headline.
  static let accentGradient = LinearGradient(
    colors: [accent, accentSoft],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  /// Verdict colors: a win, a loss and a tie are never told by color alone (each also has a word and a symbol).
  static let positive = Color.green
  static let negative = Color.orange
}

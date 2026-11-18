import SwiftUIWeb

/// The page frame every page shares, so the column, the margins and the gaps are the same everywhere: one content width,
/// one margin, one vertical rhythm and one card grid.
enum SiteLayout {
  /// The width of the content column of every page, and of the header above it.
  static let contentWidth: CGFloat = 1040
  /// The longest line of running text inside the column, so a paragraph stays readable on a wide screen.
  static let readingWidth: CGFloat = 720
  /// The column width from which the components list and its entry sit side by side.
  static let splitWidth: CGFloat = 720

  /// The margin on each side of the column, the same on every screen: the column is centered once the screen is wider
  /// than `contentWidth` and the margins.
  static let gutter: CGFloat = 20

  /// The space above the first thing on a page and below the last.
  static let pageInset: CGFloat = 32
  /// Between the sections of a page.
  static let sectionSpacing: CGFloat = 40
  /// Between the pieces of one section: a heading and what it introduces, the rows of a card.
  static let blockSpacing: CGFloat = 12

  /// Between the cards of a grid, across and down.
  static let gridSpacing: CGFloat = 16
  /// The narrowest card of a grid of statements (three columns in the full column).
  static let cardMinWidth: CGFloat = 280
  /// The narrowest card of a grid of numbers (four columns in the full column).
  static let statCardMinWidth: CGFloat = 200
  /// The narrowest animation card: its live demo needs the room.
  static let demoCardMinWidth: CGFloat = 322

  static let cardPadding: CGFloat = 16
  static let cornerRadius: CGFloat = 12
}

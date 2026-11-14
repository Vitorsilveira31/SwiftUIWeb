import SwiftUIWeb

/// Sizes the pages share, so the reading column and the gaps are the same everywhere.
enum SiteLayout {
  static let readingWidth: CGFloat = 720
  static let wideWidth: CGFloat = 1040
  /// The column width from which a list and its detail sit side by side.
  static let splitWidth: CGFloat = 720
  static let gutter: CGFloat = 20
  static let sectionSpacing: CGFloat = 28
  static let blockSpacing: CGFloat = 12
  static let cornerRadius: CGFloat = 12
}

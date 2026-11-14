import SwiftUIWeb

/// The measures of Stayly.
enum StaylyLayout {
  /// At or below this width (a phone) the filters open in a sheet; above it they sit beside the results.
  static let compactWidth: CGFloat = 600
  static let filterWidth: CGFloat = 280
  static let formWidth: CGFloat = 720
  static let resultsWidth: CGFloat = 1_080
  static let detailWidth: CGFloat = 1_080
  static let cardRadius: CGFloat = 14
  static let cardPictureHeight: CGFloat = 220
  static let thumbnailSize: CGFloat = 76
}

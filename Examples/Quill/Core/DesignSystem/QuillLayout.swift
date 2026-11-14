import SwiftUIWeb

/// The measures of Quill. The three columns of a wide window need `railWidth + feedMinWidth + sidebarWidth`; below that the
/// phone layout (a feed and a bottom bar) takes over.
enum QuillLayout {
  static let railWidth: CGFloat = 232
  static let feedMinWidth: CGFloat = 520
  static let feedMaxWidth: CGFloat = 600
  static let sidebarWidth: CGFloat = 300
  static let avatarSize: CGFloat = 40
  /// The most characters a post can have, as on the service Quill imitates.
  static let postLimit = 280
}

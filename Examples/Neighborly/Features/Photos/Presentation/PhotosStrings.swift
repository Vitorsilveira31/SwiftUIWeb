/// The words of the Photos tab.
enum PhotosStrings {
  static let title = "Photos"
  static let albumsLoading = "Loading albums…"
  static let albumsFailed = "The albums could not load"
  static let noAlbums = "No albums yet"
  static let picturesLoading = "Loading pictures…"
  static let picturesFailed = "The pictures could not load"
  static let noPictures = "This album has no pictures yet"
  static let retry = "Try again"
  static let back = "Albums"
  static let previous = "Previous picture"
  static let next = "Next picture"
  static let allPictures = "All pictures"
  static func openAlbum(_ title: String) -> String { "Open \(title)" }
  static func showPicture(_ title: String) -> String { "Show \(title)" }
  static func albumsOf(_ name: String) -> String { "Albums of \(name)" }
}

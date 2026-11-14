/// Where the pictures of the mock API are (`Tools/mock-jsonplaceholder.mjs` draws them from a number, so no image host is needed).
public enum PlaceholderImage {
  public static let base = "/api"

  /// A landscape for photo `id`, `width` by `height` points.
  public static func photo(_ id: Int, width: Int = 900, height: Int = 900) -> String {
    "\(base)/images/photo/\(id).svg?w=\(width)&h=\(height)"
  }

  /// A small square of photo `id`.
  public static func thumbnail(_ id: Int) -> String { "\(base)/images/thumb/\(id).svg" }

  /// A wide picture, for headers and banners.
  public static func cover(_ id: Int, width: Int = 1500, height: Int = 500) -> String {
    "\(base)/images/cover/\(id).svg?w=\(width)&h=\(height)"
  }

  /// A portrait of user `id`, `size` points square.
  public static func avatar(_ id: Int, size: Int = 128) -> String { "\(base)/images/avatar/\(id).svg?size=\(size)" }
}

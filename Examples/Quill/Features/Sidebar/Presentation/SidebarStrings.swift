/// The words of the right column.
enum SidebarStrings {
  static let trends = "Trends for you"
  static let trending = "Trending"
  static let whoToFollow = "Who to follow"
  static let follow = "Follow"
  static let followed = "Followed"
  static let loading = "Loading…"
  static let failedTitle = "This could not load"
  static let retry = "Try again"

  static func posts(_ count: Int) -> String { "\(Numbers.compact(count)) posts" }
}

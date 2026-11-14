/// The words of the feed.
enum FeedStrings {
  static let yourStory = "Your story"
  static let loading = "Loading the feed…"
  static let failedTitle = "The feed could not load"
  static let retry = "Try again"
  static let loadMore = "Show more"
  static let endOfFeed = "You are all caught up"
  static let like = "Like"
  static let unlike = "Unlike"
  static let comment = "Comment"
  static let save = "Save"
  static let unsave = "Remove from saved"
  static let share = "Share"

  static func likes(_ count: Int) -> String { count == 1 ? "1 like" : "\(Numbers.compact(count)) likes" }

  static func viewComments(_ count: Int) -> String { count == 1 ? "View the comment" : "View all \(count) comments" }

  static func storyLabel(_ name: String) -> String { "\(name)'s story" }
}

/// The words of the feed: the composer, the posts and the comments under them.
enum FeedStrings {
  static let composerPrompt = "What is on your mind?"
  static let post = "Post"
  static let sendFailed = "The post was not shared. Try again."
  static let loading = "Loading the feed…"
  static let failedTitle = "The feed could not load"
  static let retry = "Try again"
  static let loadMore = "Show more"
  static let endOfFeed = "You are all caught up"
  static let empty = "Nothing has been shared yet. Be the first."
  static let emptyGroup = "No posts from this group yet."
  static let like = "Like"
  static let unlike = "Unlike"
  static let comment = "Comment"
  static let clearGroup = "Show everyone"
  static let commentPrompt = "Write a comment…"
  static let loadingComments = "Loading comments…"
  static let commentsFailed = "The comments could not load"
  static let commentFailed = "The comment was not sent. Try again."

  static func reactions(_ count: Int) -> String { count == 1 ? "1 like" : "\(count) likes" }

  static func comments(_ count: Int) -> String { count == 1 ? "1 comment" : "\(count) comments" }

  static func groupTitle(_ city: String) -> String { "Neighbors in \(city)" }
}

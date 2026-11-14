/// The words of the timeline.
enum TimelineStrings {
  static let forYou = "For you"
  static let following = "Following"
  static let loading = "Loading posts…"
  static let failedTitle = "The timeline could not load"
  static let retry = "Try again"
  static let showMore = "Show more"
  static let caughtUp = "You are all caught up"
  static let empty = "Nothing here yet"
  static let like = "Like"
  static let unlike = "Unlike"
  static let repost = "Repost"
  static let undoRepost = "Undo repost"
  static let reply = "Reply"

  static func title(for feed: QuillFeed) -> String {
    switch feed {
    case .forYou: return forYou
    case .following: return following
    }
  }
}

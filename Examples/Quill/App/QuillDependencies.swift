import CloneKit

/// What Quill needs from the outside, in one place: a test builds it with doubles, the app with `live`.
struct QuillDependencies {
  let loadTimeline: any LoadTimelineUseCase
  let publishPost: any PublishPostUseCase
  let loadReplies: any LoadRepliesUseCase
  let addReply: any AddReplyUseCase
  let loadWhoToFollow: any LoadWhoToFollowUseCase
  let loadTrends: any LoadTrendsUseCase

  /// The person using Quill: the author of the posts and replies they write.
  static let currentUserID = 1

  static var live: QuillDependencies {
    let client = PlaceholderClient()
    let timeline = LiveTimelineRepository(client: client, currentUserID: currentUserID)
    let replies = LiveRepliesRepository(client: client)
    let sidebar = LiveSidebarRepository(client: client, currentUserID: currentUserID)
    return QuillDependencies(
      loadTimeline: DefaultLoadTimelineUseCase(repository: timeline),
      publishPost: DefaultPublishPostUseCase(repository: timeline),
      loadReplies: DefaultLoadRepliesUseCase(repository: replies),
      addReply: DefaultAddReplyUseCase(repository: replies),
      loadWhoToFollow: DefaultLoadWhoToFollowUseCase(repository: sidebar),
      loadTrends: DefaultLoadTrendsUseCase(repository: sidebar)
    )
  }
}

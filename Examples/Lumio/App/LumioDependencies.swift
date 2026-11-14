import CloneKit

/// What Lumio needs from the outside, in one place: a test builds it with doubles, the app with `live`.
struct LumioDependencies {
  let loadFeed: any LoadFeedUseCase
  let loadStories: any LoadStoriesUseCase
  let loadComments: any LoadCommentsUseCase
  let addComment: any AddCommentUseCase
  let loadExplore: any LoadExploreUseCase
  let loadProfile: any LoadProfileUseCase
  /// The person using Lumio: whose profile the Profile tab shows.
  let currentUserID: Int

  static var live: LumioDependencies {
    let client = PlaceholderClient()
    let feed = LiveFeedRepository(client: client)
    return LumioDependencies(
      loadFeed: DefaultLoadFeedUseCase(repository: feed),
      loadStories: DefaultLoadStoriesUseCase(repository: feed),
      loadComments: DefaultLoadCommentsUseCase(repository: LiveCommentsRepository(client: client)),
      addComment: DefaultAddCommentUseCase(repository: LiveCommentsRepository(client: client)),
      loadExplore: DefaultLoadExploreUseCase(repository: LiveExploreRepository(client: client)),
      loadProfile: DefaultLoadProfileUseCase(repository: LiveProfileRepository(client: client)),
      currentUserID: 1
    )
  }
}

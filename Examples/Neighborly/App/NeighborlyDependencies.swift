import CloneKit

/// What Neighborly needs from the outside, in one place: a test builds it with doubles, the app with `live`.
struct NeighborlyDependencies {
  let loadFeed: any LoadFeedUseCase
  let publishPost: any PublishPostUseCase
  let loadComments: any LoadCommentsUseCase
  let addComment: any AddCommentUseCase
  let loadPeople: any LoadPeopleUseCase
  let loadAlbums: any LoadAlbumsUseCase
  let loadPhotos: any LoadPhotosUseCase
  let loadProfile: any LoadProfileUseCase
  /// The person using Neighborly: they post and comment as this user, and their profile is the first one the Profile tab shows.
  let currentUserID: Int

  static var live: NeighborlyDependencies {
    let client = PlaceholderClient()
    let currentUserID = 1
    let feed = LiveFeedRepository(client: client, currentUserID: currentUserID)
    let comments = LiveCommentsRepository(client: client, currentUserID: currentUserID)
    let photos = LivePhotosRepository(client: client)
    return NeighborlyDependencies(
      loadFeed: DefaultLoadFeedUseCase(repository: feed),
      publishPost: DefaultPublishPostUseCase(repository: feed),
      loadComments: DefaultLoadCommentsUseCase(repository: comments),
      addComment: DefaultAddCommentUseCase(repository: comments),
      loadPeople: DefaultLoadPeopleUseCase(repository: LivePeopleRepository(client: client)),
      loadAlbums: DefaultLoadAlbumsUseCase(repository: photos),
      loadPhotos: DefaultLoadPhotosUseCase(repository: photos),
      loadProfile: DefaultLoadProfileUseCase(repository: LiveProfileRepository(client: client)),
      currentUserID: currentUserID
    )
  }
}

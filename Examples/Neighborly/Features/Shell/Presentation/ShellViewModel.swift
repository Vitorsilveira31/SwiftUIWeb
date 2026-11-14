import SwiftUIWeb

/// The frame's state: the tab on screen, the screens' own view models, and the moves between them (a profile, a group, the albums).
@MainActor @Observable
final class ShellViewModel {
  private(set) var tab = NeighborlyTab.home
  let currentUserID: Int
  let feed: FeedViewModel
  let contacts: ContactsViewModel
  let photos: PhotosViewModel
  let profile: ProfileViewModel
  private var started = false

  init(dependencies: NeighborlyDependencies) {
    currentUserID = dependencies.currentUserID
    feed = FeedViewModel(loadFeed: dependencies.loadFeed, publish: dependencies.publishPost, loadComments: dependencies.loadComments, addComment: dependencies.addComment)
    contacts = ContactsViewModel(load: dependencies.loadPeople)
    photos = PhotosViewModel(personID: dependencies.currentUserID, loadAlbums: dependencies.loadAlbums, loadPhotos: dependencies.loadPhotos)
    profile = ProfileViewModel(userID: dependencies.currentUserID, load: dependencies.loadProfile)
  }

  /// The first page of the feed, the contacts, the albums and the profile of the reader, loaded together, once.
  func start() async {
    guard !started else { return }
    started = true
    async let posts: Void = feed.load()
    async let people: Void = contacts.load()
    async let albums: Void = photos.load()
    async let person: Void = profile.load()
    _ = await (posts, people, albums, person)
  }

  /// The albums of the person picked, with no album open.
  func showPhotos() {
    tab = .photos
    photos.closeAlbum()
  }

  /// Home, with everyone's posts.
  func goHome() {
    tab = .home
    feed.setGroup(nil)
  }

  /// Home, with the posts of one city's neighbors.
  func showGroup(_ city: String) {
    tab = .home
    feed.setGroup(city)
  }

  /// A person's profile on the Profile tab.
  func openPerson(_ id: Int) {
    tab = .profile
    Task { await profile.show(userID: id) }
  }
}

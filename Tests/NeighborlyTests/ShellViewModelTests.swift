import Testing
@testable import Neighborly

@MainActor
struct ShellViewModelTests {
  /// The dependencies a shell needs, built from doubles: one feed, the people, the photos and the profiles.
  private func make(feed: StubFeed = StubFeed(), people: StubPeople = StubPeople(), photos: StubPhotos = StubPhotos(), profiles: StubProfiles = StubProfiles()) -> ShellViewModel {
    let comments = StubComments()
    return ShellViewModel(dependencies: NeighborlyDependencies(
      loadFeed: feed,
      publishPost: feed,
      loadComments: comments,
      addComment: comments,
      loadPeople: people,
      loadAlbums: photos,
      loadPhotos: photos,
      loadProfile: profiles,
      currentUserID: 1
    ))
  }

  @Test func startLoadsTheFeedAndThePeopleOnce() async {
    let feed = StubFeed(pages: [1: [post(1)]])
    let model = make(feed: feed)
    await model.start()
    await model.start()
    #expect(model.feed.state == .loaded)
    #expect(model.contacts.people.count == 3)
    #expect(feed.requested == [1])
  }

  @Test func aGroupGoesHomeWithThatCity() async {
    let model = make(feed: StubFeed(pages: [1: [post(1, by: ana), post(2, by: bruno)]]))
    await model.start()
    model.showPhotos()
    model.showGroup("Porto")
    #expect(model.tab == .home)
    #expect(model.feed.visiblePosts.map(\.id) == [2])
    model.goHome()
    #expect(model.feed.group == nil)
  }

  @Test func openingAPersonShowsTheirProfileOnTheProfileTab() async {
    let profiles = StubProfiles()
    profiles.profiles[2] = NeighborlyProfile(user: bruno, coverURL: "/cover.svg", postCount: 2, albumCount: 1, friends: [ana])
    let model = make(profiles: profiles)
    model.openPerson(2)
    #expect(model.tab == .profile)
    for _ in 0..<100 where model.profile.state != .loaded { await Task.yield() }
    #expect(model.profile.profile?.user.id == 2)
    #expect(model.profile.userID == 2)
  }
}

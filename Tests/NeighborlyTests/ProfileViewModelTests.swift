import Testing
@testable import Neighborly

@MainActor
struct ProfileViewModelTests {
  @Test func showingAnotherPersonReplacesTheProfile() async {
    let stub = StubProfiles()
    stub.profiles[1] = NeighborlyProfile(user: ana, coverURL: "/a.svg", postCount: 1, albumCount: 0, friends: [])
    stub.profiles[2] = NeighborlyProfile(user: bruno, coverURL: "/b.svg", postCount: 2, albumCount: 1, friends: [ana])
    let model = ProfileViewModel(userID: 1, load: stub)
    await model.load()
    #expect(model.profile?.user.id == 1)
    await model.show(userID: 2)
    #expect(model.userID == 2)
    #expect(model.profile?.user.id == 2)
    #expect(model.profile?.friends.map(\.id) == [1])
  }

  @Test func aMissingProfileSaysSo() async {
    let model = ProfileViewModel(userID: 9, load: StubProfiles())
    await model.load()
    #expect(model.state == .failed(FailureText.unreachable))
    #expect(model.profile == nil)
  }
}

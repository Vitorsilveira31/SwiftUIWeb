import Testing
@testable import Quill

@MainActor
struct SidebarViewModelTests {
  @Test func loadingShowsThePeopleAndTheTrends() async {
    let people = StubWhoToFollow()
    let trends = StubTrends()
    trends.trends = [QuillTrend(id: 1, topic: "Brave Harbors", posts: 120)]
    let model = SidebarViewModel(loadWhoToFollow: people, loadTrends: trends)
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.people == [bruno])
    #expect(model.trends.map(\.topic) == ["Brave Harbors"])
  }

  @Test func aFollowIsKeptUntilItIsUndone() {
    let model = SidebarViewModel(loadWhoToFollow: StubWhoToFollow(), loadTrends: StubTrends())
    model.toggleFollow(bruno)
    #expect(model.isFollowing(bruno))
    model.toggleFollow(bruno)
    #expect(!model.isFollowing(bruno))
  }

  @Test func aFailureSaysSo() async {
    let people = StubWhoToFollow()
    people.fails = true
    let model = SidebarViewModel(loadWhoToFollow: people, loadTrends: StubTrends())
    await model.load()
    #expect(model.state == .failed(FailureText.unreachable))
  }
}

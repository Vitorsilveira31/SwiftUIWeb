import Testing
@testable import Quill

@MainActor
struct TimelineViewModelTests {
  private func make(_ timeline: StubTimeline = StubTimeline(), thread: StubThread = StubThread()) -> TimelineViewModel {
    TimelineViewModel(loadTimeline: timeline, loadReplies: thread, addReply: thread)
  }

  @Test func loadingShowsTheFirstPageOfTheForYouFeed() async {
    let stub = StubTimeline()
    stub.pages[.forYou] = [1: [post(3), post(2)]]
    let model = make(stub)
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.posts.map(\.id) == [3, 2])
    #expect(stub.requested == ["forYou:1"])
    #expect(!model.reachedEnd)
  }

  @Test func theFollowingFeedIsOnePageAndSaysSo() async {
    let stub = StubTimeline()
    stub.pages[.following] = [1: [post(9, by: bruno)]]
    let model = make(stub)
    await model.select(.following)
    #expect(model.feed == .following)
    #expect(model.posts.map(\.id) == [9])
    #expect(model.reachedEnd)
    await model.loadMore()
    #expect(stub.requested == ["following:1"])
  }

  @Test func showMoreAppendsThePageAndAShortPageIsTheLastOne() async {
    let stub = StubTimeline()
    stub.pages[.forYou] = [1: [post(10), post(9)], 2: [post(8)]]
    let model = make(stub)
    await model.load()
    await model.loadMore()
    #expect(model.posts.map(\.id) == [10, 9, 8])
    #expect(!model.reachedEnd)
    await model.loadMore()
    #expect(model.reachedEnd)
  }

  @Test func aFailedLoadSaysSo() async {
    let stub = StubTimeline()
    stub.fails = true
    let model = make(stub)
    await model.load()
    #expect(model.state == .failed(FailureText.unreachable))
    #expect(model.posts.isEmpty)
  }

  @Test func likesAndRepostsToggleAndCountTheReadersOwnAction() {
    let model = make()
    let liked = post(1, likes: 10)
    model.toggleLike(liked)
    #expect(model.isLiked(liked))
    #expect(model.likes(of: liked) == 11)
    model.toggleLike(liked)
    #expect(model.likes(of: liked) == 10)
    model.toggleRepost(liked)
    #expect(model.reposts(of: liked) == 3)
    model.toggleRepost(liked)
    #expect(model.reposts(of: liked) == 2)
  }

  @Test func aPostTheReaderWroteGoesToTheTop() {
    let model = make()
    model.prepend(post(1))
    model.prepend(post(2))
    #expect(model.posts.map(\.id) == [2, 1])
  }

  @Test func repliesSentInAThreadShowOnThePostWhenTheThreadCloses() async throws {
    let thread = StubThread()
    let model = make(thread: thread)
    let target = post(4, replies: 5)
    model.prepend(target)
    model.open(target)
    let detail = try #require(model.thread)
    detail.draft = "agreed"
    await detail.send()
    #expect(thread.sent == ["agreed"])
    #expect(model.replies(of: model.posts[0]) == 5)
    model.finishThread()
    #expect(model.opened == nil)
    #expect(model.replies(of: model.posts[0]) == 6)
  }
}

import Testing
@testable import Neighborly

@MainActor
struct FeedViewModelTests {
  private func make(_ feed: StubFeed, comments: StubComments = StubComments()) -> FeedViewModel {
    FeedViewModel(loadFeed: feed, publish: feed, loadComments: comments, addComment: comments)
  }

  @Test func loadingShowsTheFirstPage() async {
    let model = make(StubFeed(pages: [1: [post(1), post(2)]]))
    #expect(model.state == .loading)
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.posts.map(\.id) == [1, 2])
  }

  @Test func aFailureSaysSoAndTryingAgainRecovers() async {
    let feed = StubFeed(pages: [1: [post(1)]])
    let model = make(feed)
    feed.fails = true
    await model.load()
    #expect(model.state == .failed(FailureText.unreachable))
    feed.fails = false
    await model.load()
    #expect(model.state == .loaded)
  }

  @Test func moreAddsTheNextPageAndAnEmptyOneEndsTheFeed() async {
    let feed = StubFeed(pages: [1: [post(1)], 2: [post(2)]])
    let model = make(feed)
    await model.load()
    await model.loadMore()
    #expect(model.posts.map(\.id) == [1, 2])
    #expect(!model.reachedEnd)
    await model.loadMore()
    #expect(model.reachedEnd)
    await model.loadMore()
    #expect(feed.requested == [1, 2, 3])
  }

  @Test func aBlankDraftCannotBeShared() async {
    let feed = StubFeed()
    let model = make(feed)
    model.draft = "   \n "
    #expect(!model.canPublish)
    await model.publishDraft()
    #expect(feed.published.isEmpty)
  }

  @Test func sharingPutsThePostFirstAndClearsTheDraft() async {
    let feed = StubFeed(pages: [1: [post(1)]])
    let model = make(feed)
    await model.load()
    model.draft = "Lovely morning on the square"
    await model.publishDraft()
    #expect(feed.published == ["Lovely morning on the square"])
    #expect(model.posts.first?.text == "Lovely morning on the square")
    #expect(model.posts.count == 2)
    #expect(model.draft == "")
    #expect(!model.publishFailed)
  }

  @Test func aFailedShareKeepsTheDraftAndSaysSo() async {
    let feed = StubFeed()
    feed.fails = true
    let model = make(feed)
    model.draft = "hello"
    await model.publishDraft()
    #expect(model.draft == "hello")
    #expect(model.publishFailed)
    #expect(model.posts.isEmpty)
  }

  @Test func likingAddsOneToTheCountAndUnlikingTakesItBack() async {
    let model = make(StubFeed(pages: [1: [post(1)]]))
    await model.load()
    let first = model.posts[0]
    #expect(model.reactions(of: first) == 10)
    model.toggleLike(first)
    #expect(model.isLiked(first))
    #expect(model.reactions(of: first) == 11)
    model.toggleLike(first)
    #expect(model.reactions(of: first) == 10)
  }

  @Test func aGroupShowsOnlyTheNeighborsOfThatCity() async {
    let model = make(StubFeed(pages: [1: [post(1, by: ana), post(2, by: bruno), post(3, by: carla)]]))
    await model.load()
    model.setGroup("Lisbon")
    #expect(model.visiblePosts.map(\.id) == [1, 3])
    model.setGroup(nil)
    #expect(model.visiblePosts.map(\.id) == [1, 2, 3])
  }

  @Test func openingAThreadLoadsItAndClosingItKeepsIt() async {
    let comments = StubComments()
    comments.comments = [NeighborlyComment(id: 1, author: "Bruno Barros", text: "hi")]
    let model = make(StubFeed(pages: [1: [post(7)]]), comments: comments)
    await model.load()
    let target = model.posts[0]
    await model.toggleThread(target)
    #expect(model.isThreadOpen(target))
    #expect(comments.loaded == [7])
    #expect(model.commentCount(of: target) == 1)
    await model.toggleThread(target)
    #expect(!model.isThreadOpen(target))
    #expect(model.thread(for: target) != nil)
    #expect(comments.loaded == [7])
  }

  @Test func aClosedThreadWithoutLoadedCommentsShowsTheCountItCameWith() async {
    let model = make(StubFeed(pages: [1: [post(4)]]))
    await model.load()
    #expect(model.commentCount(of: model.posts[0]) == 5)
  }
}

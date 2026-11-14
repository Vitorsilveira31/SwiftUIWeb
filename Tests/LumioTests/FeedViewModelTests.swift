import Testing
@testable import Lumio

@MainActor
struct FeedViewModelTests {
  private func make(_ feed: StubFeed, comments: StubComments = StubComments()) -> FeedViewModel {
    FeedViewModel(loadFeed: feed, loadStories: feed, loadComments: comments, addComment: comments)
  }

  @Test func loadingShowsTheFirstPageAndTheStories() async {
    let model = make(StubFeed(pages: [1: [post(1), post(2)]]))
    #expect(model.state == .loading)
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.posts.map(\.id) == [1, 2])
    #expect(model.stories.map(\.id) == [1, 2])
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
    #expect(model.reachedEnd == false)
    await model.loadMore()
    #expect(model.reachedEnd == true)
    await model.loadMore()
    #expect(feed.requested == [1, 2, 3])
  }

  @Test func moreWaitsForTheFirstPage() async {
    let feed = StubFeed(pages: [1: [post(1)]])
    let model = make(feed)
    await model.loadMore()
    #expect(feed.requested.isEmpty)
  }

  @Test func likingAddsOneToTheCountAndUnlikingTakesItBack() async {
    let model = make(StubFeed(pages: [1: [post(1)]]))
    await model.load()
    let first = model.posts[0]
    #expect(model.likes(of: first) == 10)
    model.toggleLike(first)
    #expect(model.isLiked(first))
    #expect(model.likes(of: first) == 11)
    model.toggleLike(first)
    #expect(model.likes(of: first) == 10)
  }

  @Test func savingIsIndependentOfLiking() async {
    let model = make(StubFeed(pages: [1: [post(1), post(2)]]))
    await model.load()
    model.toggleSave(model.posts[0])
    #expect(model.isSaved(model.posts[0]))
    #expect(!model.isSaved(model.posts[1]))
    #expect(!model.isLiked(model.posts[0]))
  }

  @Test func theCommentsModelIsForThePostItWasAskedFor() async {
    let comments = StubComments()
    comments.comments = [LumioComment(id: 1, author: "x", text: "hi")]
    let model = make(StubFeed(pages: [1: [post(7)]]), comments: comments)
    await model.load()
    let commentsModel = model.commentsModel(for: model.posts[0])
    await commentsModel.loadComments()
    #expect(commentsModel.comments.map(\.text) == ["hi"])
  }
}

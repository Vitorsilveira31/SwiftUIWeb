import Testing
@testable import Lumio

@MainActor
struct CommentsViewModelTests {
  private func make(_ stub: StubComments) -> CommentsViewModel { CommentsViewModel(postID: 3, load: stub, add: stub) }

  @Test func loadingShowsTheComments() async {
    let stub = StubComments()
    stub.comments = [LumioComment(id: 1, author: "a", text: "one")]
    let model = make(stub)
    await model.loadComments()
    #expect(model.state == .loaded)
    #expect(model.comments.count == 1)
  }

  @Test func aCommentOfNothingButSpacesCannotBeSent() async {
    let stub = StubComments()
    let model = make(stub)
    model.draft = "   "
    #expect(!model.canSend)
    await model.send()
    #expect(stub.sent.isEmpty)
    model.draft = " hi "
    #expect(model.canSend)
  }

  @Test func sendingAddsTheCommentAndClearsTheDraft() async {
    let stub = StubComments()
    let model = make(stub)
    model.draft = "lovely"
    await model.send()
    #expect(stub.sent == ["lovely"])
    #expect(model.comments.map(\.text) == ["lovely"])
    #expect(model.draft == "")
    #expect(!model.sendFailed)
  }

  @Test func aFailedSendKeepsTheDraftAndSaysSo() async {
    let stub = StubComments()
    stub.fails = true
    let model = make(stub)
    model.draft = "lovely"
    await model.send()
    #expect(model.draft == "lovely")
    #expect(model.sendFailed)
    #expect(model.comments.isEmpty)
  }
}

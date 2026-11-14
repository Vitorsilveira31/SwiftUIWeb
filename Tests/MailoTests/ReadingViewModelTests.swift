import Testing
@testable import Mailo

@MainActor
struct ReadingViewModelTests {
  private func make(_ stub: StubThread) -> ReadingViewModel {
    ReadingViewModel(message: message(3), load: stub, reply: stub)
  }

  @Test func loadingShowsTheThread() async {
    let stub = StubThread()
    stub.replies = [MailReply(id: 1, author: carla, body: "Yes")]
    let model = make(stub)
    await model.loadReplies()
    #expect(model.state == .loaded)
    #expect(model.replies.count == 1)
  }

  @Test func aFailedThreadSaysSo() async {
    let stub = StubThread()
    stub.fails = true
    let model = make(stub)
    await model.loadReplies()
    #expect(model.state == .failed(FailureText.unreachable))
  }

  @Test func aReplyOfNothingButSpacesCannotBeSent() async {
    let stub = StubThread()
    let model = make(stub)
    model.draft = "   "
    #expect(!model.canSend)
    await model.send()
    #expect(stub.replied.isEmpty)
  }

  @Test func sendingAddsTheReplyToTheThreadAndClearsTheDraft() async {
    let stub = StubThread()
    let model = make(stub)
    await model.loadReplies()
    model.draft = "Sounds good"
    await model.send()
    #expect(stub.replied == ["Sounds good"])
    #expect(model.replies.map(\.body) == ["Sounds good"])
    #expect(model.draft == "")
    #expect(!model.replyFailed)
  }

  @Test func aFailedReplyKeepsTheDraftAndSaysSo() async {
    let stub = StubThread()
    let model = make(stub)
    model.draft = "Sounds good"
    stub.fails = true
    await model.send()
    #expect(model.draft == "Sounds good")
    #expect(model.replyFailed)
    #expect(model.replies.isEmpty)
  }
}

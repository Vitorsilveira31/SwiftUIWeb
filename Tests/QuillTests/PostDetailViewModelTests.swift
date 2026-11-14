import Testing
@testable import Quill

@MainActor
struct PostDetailViewModelTests {
  private func make(_ thread: StubThread) -> PostDetailViewModel {
    PostDetailViewModel(post: post(3), loadReplies: thread, addReply: thread)
  }

  @Test func loadingShowsTheReplies() async {
    let thread = StubThread()
    thread.replies = [QuillReply(id: 1, name: "eliseo", text: "hi", avatarURL: "/a.svg")]
    let model = make(thread)
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.replies.map(\.name) == ["eliseo"])
  }

  @Test func sendingAddsTheReplyAndCountsIt() async {
    let thread = StubThread()
    let model = make(thread)
    model.draft = "agreed"
    await model.send()
    #expect(model.replies.map(\.text) == ["agreed"])
    #expect(model.draft == "")
    #expect(model.sentCount == 1)
  }

  @Test func aBlankReplyCannotBeSent() async {
    let thread = StubThread()
    let model = make(thread)
    model.draft = "  \n "
    #expect(!model.canSend)
    await model.send()
    #expect(thread.sent.isEmpty)
  }

  @Test func aFailedReplyKeepsTheDraftAndSaysSo() async {
    let thread = StubThread()
    thread.fails = true
    let model = make(thread)
    model.draft = "agreed"
    await model.send()
    #expect(model.draft == "agreed")
    #expect(model.sendFailed)
    #expect(model.replies.isEmpty)
  }
}

import Testing
@testable import Quill

@MainActor
struct ComposerViewModelTests {
  private func make(_ stub: StubTimeline = StubTimeline()) -> ComposerViewModel { ComposerViewModel(publish: stub) }

  @Test func aPostOfNothingButSpacesCannotBeSent() async {
    let stub = StubTimeline()
    let model = make(stub)
    model.draft = "   "
    #expect(!model.canPost)
    await model.post { _ in }
    #expect(stub.published.isEmpty)
    model.draft = " hi "
    #expect(model.canPost)
  }

  @Test func aPostOverTheLimitCannotBeSent() {
    let model = make()
    model.draft = String(repeating: "a", count: QuillLayout.postLimit + 1)
    #expect(model.isOverLimit)
    #expect(!model.canPost)
    #expect(model.remaining == -1)
  }

  @Test func postingClearsTheDraftAndHandsOverThePost() async {
    let stub = StubTimeline()
    let model = make(stub)
    let recorder = Recorder<QuillPost>()
    model.draft = "lovely"
    await model.post { recorder.values.append($0) }
    #expect(stub.published == ["lovely"])
    #expect(recorder.values.map(\.text) == ["post 101"])
    #expect(model.draft == "")
    #expect(!model.sendFailed)
  }

  @Test func aFailedPostKeepsTheDraftAndSaysSo() async {
    let stub = StubTimeline()
    stub.publishFails = true
    let model = make(stub)
    model.draft = "lovely"
    await model.post { _ in }
    #expect(model.draft == "lovely")
    #expect(model.sendFailed)
  }
}

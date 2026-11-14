import Testing
@testable import Mailo

@MainActor
struct ComposeViewModelTests {
  private func make(_ thread: StubThread, memory: MailboxState = MailboxState(), draft: MailMessage? = nil) -> ComposeViewModel {
    ComposeViewModel(draft: draft, memory: memory, sender: thread)
  }

  @Test func aRecipientNeedsAnAddress() {
    let model = make(StubThread())
    model.to = "bruno"
    #expect(!model.canSend)
    model.to = "bruno.barros@example.test"
    #expect(model.canSend)
  }

  @Test func sendingSendsTheMessageAndRemovesItsDraft() async {
    let thread = StubThread()
    let memory = MailboxState()
    let model = make(thread, memory: memory)
    model.to = "bruno.barros@example.test"
    model.subject = "Hi"
    model.body = "Hello"
    model.saveDraft()
    #expect(memory.drafts.count == 1)
    let sent = await model.send()
    #expect(sent)
    #expect(thread.sent.map(\.subject) == ["Hi"])
    #expect(thread.sent.first?.recipient == "bruno.barros@example.test")
    #expect(memory.drafts.isEmpty)
  }

  @Test func aFailedSendKeepsTheMessageAndSaysSo() async {
    let thread = StubThread()
    thread.fails = true
    let memory = MailboxState()
    let model = make(thread, memory: memory)
    model.to = "bruno.barros@example.test"
    model.saveDraft()
    let sent = await model.send()
    #expect(!sent)
    #expect(model.failed)
    #expect(memory.drafts.count == 1)
  }

  @Test func savingAgainUpdatesTheSameDraft() {
    let memory = MailboxState()
    let model = make(StubThread(), memory: memory)
    model.to = "bruno.barros@example.test"
    model.body = "First"
    model.saveDraft()
    model.body = "Second"
    model.saveDraft()
    #expect(memory.drafts.count == 1)
    #expect(memory.drafts.first?.body == "Second")
  }

  @Test func aDraftOpenedAgainIsTheOneThatWasSaved() {
    let memory = MailboxState()
    let draftID = memory.saveDraft(id: nil, to: "bruno.barros@example.test", subject: "Lunch", body: "Friday?")
    let draft = memory.drafts.first { $0.id == draftID }
    let model = make(StubThread(), memory: memory, draft: draft)
    #expect(model.subject == "Lunch")
    #expect(model.to == "bruno.barros@example.test")
    model.body = "Monday?"
    model.saveDraft()
    #expect(memory.drafts.count == 1)
    #expect(memory.drafts.first?.body == "Monday?")
  }
}

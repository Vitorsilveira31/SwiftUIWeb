import Testing
@testable import Mailo

@MainActor
struct MailboxViewModelTests {
  private func make(_ stub: StubMailbox, memory: MailboxState = MailboxState()) -> MailboxViewModel {
    MailboxViewModel(list: stub, remove: stub, memory: memory)
  }

  @Test func theInboxListsTheReceivedMessagesAsTheServiceGivesThem() async {
    let stub = StubMailbox()
    stub.messages = [message(3), message(1), message(2)]
    let model = make(stub)
    await model.load()
    #expect(stub.scopes == [.received])
    #expect(model.messages.map(\.id) == [3, 1, 2])
    #expect(model.state == .loaded)
  }

  @Test func theUnreadCountIsTheReceivedMessagesNotYetRead() async {
    let stub = StubMailbox()
    stub.messages = [message(1), message(2), message(3, from: MailoAccount.person)]
    let model = make(stub)
    await model.load()
    #expect(model.unreadCount == 2)
    model.markOpened(1)
    #expect(model.unreadCount == 1)
  }

  @Test func aFailedListingSaysSo() async {
    let stub = StubMailbox()
    stub.fails = true
    let model = make(stub)
    await model.load()
    #expect(model.state == .failed(FailureText.unreachable))
  }

  @Test func aPageHoldsTwentyMessagesAndTheOthersAreOneClickAway() async {
    let stub = StubMailbox()
    stub.messages = (1...25).map { message(26 - $0) }
    let model = make(stub)
    await model.load()
    #expect(model.pageMessages.count == 20)
    #expect(model.rangeLabel == "1-20 of 25")
    #expect(!model.hasNewer)
    model.showOlder()
    #expect(model.pageMessages.count == 5)
    #expect(model.rangeLabel == "21-25 of 25")
    #expect(!model.hasOlder)
    model.showNewer()
    #expect(model.page == 1)
  }

  @Test func aSearchGoesToTheServiceAsItsQuery() async {
    let stub = StubMailbox()
    let model = make(stub)
    model.query = "harbor"
    await model.search()
    #expect(stub.searches == ["harbor"])
  }

  @Test func selectAllTakesThePageAndAClickClearsIt() async {
    let stub = StubMailbox()
    stub.messages = (1...25).map { message($0) }
    let model = make(stub)
    await model.load()
    model.toggleSelectAll()
    #expect(model.selected.count == 20)
    #expect(model.allOnPageSelected)
    model.toggleSelectAll()
    #expect(model.selected.isEmpty)
  }

  @Test func aStarredMessageIsListedInStarred() async {
    let stub = StubMailbox()
    stub.messages = [message(1), message(2)]
    let model = make(stub)
    await model.load()
    model.toggleStar(2)
    await model.select(.starred)
    #expect(model.messages.map(\.id) == [2])
    #expect(stub.scopes.last == .all)
  }

  @Test func deletingMovesToTheTrashAndHidesFromTheInbox() async {
    let stub = StubMailbox()
    stub.messages = [message(1), message(2), message(3)]
    let model = make(stub)
    await model.load()
    model.toggleSelection(2)
    await model.delete(model.selected)
    #expect(model.messages.map(\.id) == [1, 3])
    #expect(model.memory.isTrashed(2))
    #expect(stub.deleted.isEmpty)
    await model.select(.trash)
    #expect(model.messages.map(\.id) == [2])
  }

  @Test func deletingFromTheTrashDeletesForGood() async {
    let stub = StubMailbox()
    stub.messages = [message(2)]
    let model = make(stub)
    await model.load()
    await model.delete([2])
    await model.select(.trash)
    await model.delete([2])
    #expect(stub.deleted == [2])
    #expect(model.messages.isEmpty)
    #expect(!model.memory.isTrashed(2))
  }

  @Test func aFailedDeleteForGoodKeepsTheMessageAndSaysSo() async {
    let stub = StubMailbox()
    stub.messages = [message(2)]
    stub.deleteFails = true
    let model = make(stub, memory: MailboxState())
    await model.load()
    await model.delete([2])
    await model.select(.trash)
    await model.delete([2])
    #expect(model.actionFailed)
    #expect(model.messages.map(\.id) == [2])
  }

  @Test func markingReadAndUnreadChangesTheMarks() async {
    let stub = StubMailbox()
    stub.messages = [message(1), message(2)]
    let model = make(stub)
    await model.load()
    model.toggleSelection(1)
    model.markSelected(unread: false)
    #expect(!model.memory.isUnread(message(1)))
    #expect(model.selected.isEmpty)
    model.toggleSelection(1)
    model.markSelected(unread: true)
    #expect(model.memory.isUnread(message(1)))
  }

  @Test func draftsAreListedFromMemoryAndNeverAskTheService() async {
    let stub = StubMailbox()
    let memory = MailboxState()
    _ = memory.saveDraft(id: nil, to: "carla.campos@example.test", subject: "Lunch", body: "Tuesday?")
    let model = make(stub, memory: memory)
    await model.select(.drafts)
    #expect(model.messages.map(\.subject) == ["Lunch"])
    #expect(model.messages.first?.isDraft == true)
    #expect(stub.scopes.isEmpty)
  }

  @Test func deletingADraftThrowsItAway() async {
    let memory = MailboxState()
    let draftID = memory.saveDraft(id: nil, to: "carla.campos@example.test", subject: "Lunch", body: "Tuesday?")
    let model = make(StubMailbox(), memory: memory)
    await model.select(.drafts)
    await model.delete([draftID])
    #expect(memory.drafts.isEmpty)
    #expect(model.messages.isEmpty)
  }
}

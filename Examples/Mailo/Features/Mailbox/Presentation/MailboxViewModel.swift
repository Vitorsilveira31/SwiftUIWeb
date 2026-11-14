import SwiftUIWeb

/// The mailbox: the folder on screen, its messages a page at a time, the selection, and the stars, trash and read marks in `memory`.
@MainActor @Observable
final class MailboxViewModel {
  static let pageSize = 20
  let memory: MailboxState
  private(set) var folder = MailFolder.inbox
  var query = ""
  private(set) var state: LoadState = .loading
  /// Every message of the folder on screen, newest first; the list shows one page of them.
  private(set) var messages: [MailMessage] = []
  private(set) var page = 1
  private(set) var selected: Set<Int> = []
  private(set) var actionFailed = false
  /// The received mail as the last inbox listing had it: the sidebar shows the unread count whatever folder is open.
  private var received: [MailMessage] = []
  private let list: any LoadMessagesUseCase
  private let remove: any DeleteMessageUseCase

  init(list: any LoadMessagesUseCase, remove: any DeleteMessageUseCase, memory: MailboxState) {
    self.list = list
    self.remove = remove
    self.memory = memory
  }

  var pageMessages: [MailMessage] {
    Array(messages.dropFirst((page - 1) * Self.pageSize).prefix(Self.pageSize))
  }

  var pageCount: Int { (messages.count + Self.pageSize - 1) / Self.pageSize }
  var hasOlder: Bool { page < pageCount }
  var hasNewer: Bool { page > 1 }

  var rangeLabel: String {
    let first = (page - 1) * Self.pageSize + 1
    return MailboxStrings.range(first: first, last: min(page * Self.pageSize, messages.count), total: messages.count)
  }

  var unreadCount: Int { received.filter { !memory.isTrashed($0.id) && memory.isUnread($0) }.count }

  var allOnPageSelected: Bool { !pageMessages.isEmpty && pageMessages.allSatisfy { selected.contains($0.id) } }

  func isSelected(_ id: Int) -> Bool { selected.contains(id) }

  func toggleSelection(_ id: Int) {
    if !selected.insert(id).inserted { selected.remove(id) }
  }

  func toggleSelectAll() {
    let ids = Set(pageMessages.map(\.id))
    if allOnPageSelected { selected.subtract(ids) } else { selected.formUnion(ids) }
  }

  func toggleStar(_ id: Int) { memory.toggleStar(id) }

  /// Opening a message reads it.
  func markOpened(_ id: Int) { memory.setUnread([id], false) }

  func markSelected(unread: Bool) {
    memory.setUnread(selected, unread)
    selected = []
  }

  func select(_ folder: MailFolder) async {
    self.folder = folder
    query = ""
    selected = []
    await load()
  }

  func search() async {
    selected = []
    await load()
  }

  func showOlder() {
    guard hasOlder else { return }
    page += 1
    selected = []
  }

  func showNewer() {
    guard hasNewer else { return }
    page -= 1
    selected = []
  }

  func load() async {
    state = .loading
    if folder == .drafts {
      messages = Array(memory.drafts.reversed())
      page = 1
      state = .loaded
      return
    }
    do {
      let fetched = try await list.execute(scope: folder.scope, search: query)
      if folder == .inbox && query.isEmpty { received = fetched }
      messages = fetched.filter { isListed($0) }
      page = 1
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  /// Deletes messages. A draft is thrown away, a message in the trash is deleted for good, any other goes to the trash.
  func delete(_ ids: Set<Int>) async {
    actionFailed = false
    var done = Set<Int>()
    if folder == .drafts {
      memory.removeDrafts(ids)
      done = ids
    } else if folder == .trash {
      for id in ids {
        do { try await remove.execute(id: id) } catch {
          actionFailed = true
          break
        }
        memory.forget(id)
        done.insert(id)
      }
      received.removeAll { done.contains($0.id) }
    } else {
      memory.trash(ids)
      done = ids
    }
    messages.removeAll { done.contains($0.id) }
    selected.subtract(done)
    page = min(page, max(1, pageCount))
  }

  /// A message stays in its folder's list only while the folder asks for it: the trash holds the trashed, the rest hold none of them.
  private func isListed(_ message: MailMessage) -> Bool {
    let trashed = memory.isTrashed(message.id)
    switch folder {
    case .inbox, .sent: return !trashed
    case .starred: return !trashed && memory.isStarred(message.id)
    case .trash: return trashed
    case .drafts: return true
    }
  }
}

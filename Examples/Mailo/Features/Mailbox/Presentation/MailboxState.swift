import SwiftUIWeb

/// What the reader did in this session, kept in memory: stars, the trash, read marks and drafts. The service keeps none of it.
@MainActor @Observable
final class MailboxState {
  private(set) var starred: Set<Int> = []
  private(set) var trashed: Set<Int> = []
  /// A message's read mark when the reader set one; without it a received message is unread and a message the account wrote is read.
  private(set) var unreadMarks: [Int: Bool] = [:]
  /// Drafts in the order they were saved.
  private(set) var drafts: [MailMessage] = []
  private var nextDraftID = 1_000_000

  func isStarred(_ id: Int) -> Bool { starred.contains(id) }
  func isTrashed(_ id: Int) -> Bool { trashed.contains(id) }
  func isUnread(_ message: MailMessage) -> Bool { unreadMarks[message.id] ?? !message.isMine }

  func toggleStar(_ id: Int) {
    if !starred.insert(id).inserted { starred.remove(id) }
  }

  func trash(_ ids: Set<Int>) { trashed.formUnion(ids) }

  func setUnread(_ ids: Set<Int>, _ unread: Bool) {
    for id in ids { unreadMarks[id] = unread }
  }

  /// A message deleted for good leaves no trace in the memory.
  func forget(_ id: Int) {
    starred.remove(id)
    trashed.remove(id)
    unreadMarks[id] = nil
  }

  /// Saves a draft, or updates the one with `id`; returns its id.
  func saveDraft(id: Int?, to: String, subject: String, body: String) -> Int {
    let draftID = id ?? nextDraftID
    if id == nil { nextDraftID += 1 }
    let draft = MailMessage(id: draftID, sender: MailoAccount.person, recipient: to, subject: subject, body: body, isDraft: true)
    if let index = drafts.firstIndex(where: { $0.id == draftID }) {
      drafts[index] = draft
    } else {
      drafts.append(draft)
    }
    return draftID
  }

  func removeDrafts(_ ids: Set<Int>) { drafts.removeAll { ids.contains($0.id) } }
}

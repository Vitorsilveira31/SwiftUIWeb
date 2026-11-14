/// The folders of the sidebar, in order. The service keeps the received and the sent mail; starred, trash and drafts are kept in memory.
enum MailFolder: CaseIterable, Hashable, Identifiable, Sendable {
  case inbox
  case starred
  case sent
  case drafts
  case trash

  var id: MailFolder { self }

  /// Which of the service's messages the folder lists (drafts list none).
  var scope: MailScope {
    switch self {
    case .inbox: .received
    case .sent: .sent
    case .starred, .drafts, .trash: .all
    }
  }
}

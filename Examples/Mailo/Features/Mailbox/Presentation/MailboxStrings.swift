/// The words of the mailbox: the folders, the list, its actions and its states.
enum MailboxStrings {
  static let loading = "Loading mail…"
  static let failedTitle = "Mail could not load"
  static let retry = "Try again"
  static let selectAll = "Select all"
  static let select = "Select message"
  static let star = "Star"
  static let unstar = "Remove star"
  static let delete = "Delete"
  static let markRead = "Mark read"
  static let markUnread = "Mark unread"
  static let older = "Older"
  static let newer = "Newer"
  static let noSubject = "(no subject)"
  static let draft = "Draft"
  static let yesterday = "Yesterday"
  static let actionFailed = "The change could not be saved. Try again."

  static func title(_ folder: MailFolder) -> String {
    switch folder {
    case .inbox: "Inbox"
    case .starred: "Starred"
    case .sent: "Sent"
    case .drafts: "Drafts"
    case .trash: "Trash"
    }
  }

  static func empty(_ folder: MailFolder) -> String {
    switch folder {
    case .inbox: "Nothing in Inbox"
    case .starred: "No starred messages"
    case .sent: "Nothing sent yet"
    case .drafts: "No drafts"
    case .trash: "Nothing in Trash"
    }
  }

  static func range(first: Int, last: Int, total: Int) -> String { "\(first)-\(last) of \(total)" }
  static func to(_ address: String) -> String { "To \(address)" }
  static func selected(_ count: Int) -> String { "\(count) selected" }
  static func date(day: Int) -> String { "Oct \(day)" }
}

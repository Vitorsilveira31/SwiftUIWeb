/// Which of the service's messages a list asks for: the ones that came in, the ones the account sent, or all of them.
enum MailScope: Hashable, Sendable {
  case received
  case sent
  case all

  /// The filter of the service's query for the scope: `userId_ne` is every user but the account.
  var filter: String {
    switch self {
    case .received: "userId_ne=\(MailoAccount.userID)"
    case .sent: "userId=\(MailoAccount.userID)"
    case .all: ""
    }
  }
}

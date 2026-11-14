/// A message. The service's post is the message: its user is the sender, its title the subject, its body the text. A sent message
/// also has the recipient it was given. A draft is kept in memory until it is sent or thrown away, and has no sender line of its own.
struct MailMessage: Identifiable, Hashable, Sendable {
  let id: Int
  let sender: MailPerson
  let recipient: String?
  let subject: String
  let body: String
  var isDraft = false

  /// Whether the account wrote this message (it is sent mail, or a draft).
  var isMine: Bool { sender == MailoAccount.person }

  /// The start of the body on one line, for the list.
  var preview: String {
    let line = body.split(separator: "\n").joined(separator: " ")
    return String(line.prefix(120))
  }
}

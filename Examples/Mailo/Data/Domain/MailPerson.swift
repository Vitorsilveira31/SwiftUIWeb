/// A person who sends or receives mail: the name and the address the service keeps for them.
struct MailPerson: Identifiable, Hashable, Sendable {
  let name: String
  let address: String

  var id: String { address }

  /// The first letters of the first two words of the name, for the avatar.
  var initials: String {
    var letters = ""
    for word in name.split(separator: " ").prefix(2) {
      if let first = word.first { letters.append(first) }
    }
    return letters
  }
}

import Foundation
@testable import CloneKit
@testable import Mailo

let bruno = MailPerson(name: "Bruno Barros", address: "bruno.barros@example.test")
let carla = MailPerson(name: "Carla Campos", address: "carla.campos@example.test")

func message(_ id: Int, from sender: MailPerson = bruno, recipient: String? = nil, subject: String = "Subject") -> MailMessage {
  MailMessage(id: id, sender: sender, recipient: recipient, subject: subject, body: "Body \(id)")
}

struct Failure: Error {}

/// Answers a listing with the messages it was given, or fails; deletes and records what it was asked.
final class StubMailbox: LoadMessagesUseCase, DeleteMessageUseCase, @unchecked Sendable {
  var messages: [MailMessage] = []
  var fails = false
  var deleteFails = false
  private(set) var scopes: [MailScope] = []
  private(set) var searches: [String] = []
  private(set) var deleted: [Int] = []

  func execute(scope: MailScope, search: String) async throws -> [MailMessage] {
    scopes.append(scope)
    searches.append(search)
    if fails { throw Failure() }
    return messages
  }

  func execute(id: Int) async throws {
    if deleteFails { throw Failure() }
    deleted.append(id)
  }
}

/// Answers a thread and a send with what the test gave, or fails.
final class StubThread: LoadRepliesUseCase, ReplyUseCase, SendMessageUseCase, @unchecked Sendable {
  var replies: [MailReply] = []
  var fails = false
  private(set) var replied: [String] = []
  private(set) var sent: [MailMessage] = []

  func execute(messageID: Int) async throws -> [MailReply] {
    if fails { throw Failure() }
    return replies
  }

  func execute(messageID: Int, text: String) async throws -> MailReply {
    if fails { throw Failure() }
    replied.append(text)
    return MailReply(id: 500 + replied.count, author: MailoAccount.person, body: text)
  }

  func execute(to: String, subject: String, body: String) async throws -> MailMessage {
    if fails { throw Failure() }
    let sentMessage = MailMessage(id: 100 + sent.count, sender: MailoAccount.person, recipient: to, subject: subject, body: body)
    sent.append(sentMessage)
    return sentMessage
  }
}

/// Answers by path, so the repositories can be tested against what the API sends.
struct StubTransport: PlaceholderTransport {
  let answers: [String: String]

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    guard let answer = answers[path] else { throw PlaceholderError.status(404) }
    return Data(answer.utf8)
  }
}

import Foundation
import Testing
@testable import CloneKit

private final class MailRecordingTransport: PlaceholderTransport, @unchecked Sendable {
  var sent: [(method: String, path: String, body: String?)] = []
  let answer: String

  init(answer: String) { self.answer = answer }

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    sent.append((method, path, body.flatMap { String(data: $0, encoding: .utf8) }))
    return Data(answer.utf8)
  }
}

struct PlaceholderClientMailTests {
  @Test func mailPostsAreFilteredAndSearched() async throws {
    let transport = MailRecordingTransport(answer: "[]")
    let client = PlaceholderClient(transport: transport)
    _ = try await client.mailPosts(filter: "userId_ne=1", search: "")
    _ = try await client.mailPosts(filter: "userId=1", search: "quiet harbor")
    _ = try await client.mailPosts(filter: "", search: "")
    #expect(transport.sent.map(\.path) == ["/api/posts?userId_ne=1", "/api/posts?userId=1&q=quiet%20harbor", "/api/posts"])
  }

  @Test func aSentMessageKeepsItsRecipient() async throws {
    let transport = MailRecordingTransport(answer: #"{"userId":1,"id":101,"title":"Hi","body":"Hello","to":"bruno.barros@example.test"}"#)
    let sent = try await PlaceholderClient(transport: transport).sendPost(userId: 1, to: "bruno.barros@example.test", title: "Hi", body: "Hello")
    #expect(sent.id == 101)
    #expect(sent.to == "bruno.barros@example.test")
    #expect(transport.sent.first?.method == "POST")
    #expect(transport.sent.first?.path == "/api/posts")
    #expect(transport.sent.first?.body?.contains("\"to\":\"bruno.barros@example.test\"") == true)
  }

  @Test func aDeletedMessageIsRequestedByItsId() async throws {
    let transport = MailRecordingTransport(answer: "{}")
    try await PlaceholderClient(transport: transport).deletePost(id: 7)
    #expect(transport.sent.map(\.method) == ["DELETE"])
    #expect(transport.sent.map(\.path) == ["/api/posts/7"])
  }
}

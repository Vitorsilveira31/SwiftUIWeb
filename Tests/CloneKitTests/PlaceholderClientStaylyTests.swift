import Foundation
import Testing
@testable import CloneKit

private final class RecordingStaylyTransport: PlaceholderTransport, @unchecked Sendable {
  var sent: [(method: String, path: String, body: String?)] = []
  let answer: String

  init(answer: String) { self.answer = answer }

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    sent.append((method, path, body.flatMap { String(data: $0, encoding: .utf8) }))
    return Data(answer.utf8)
  }
}

struct PlaceholderClientStaylyTests {
  @Test func albumsAreRequestedAsAWhole() async throws {
    let transport = RecordingStaylyTransport(answer: #"[{"userId":1,"id":3,"title":"t"}]"#)
    let albums = try await PlaceholderClient(transport: transport).albums()
    #expect(transport.sent.map(\.path) == ["/api/albums"])
    #expect(albums.first?.id == 3)
  }

  @Test func aPostIsRequestedByItsNumber() async throws {
    let transport = RecordingStaylyTransport(answer: #"{"userId":1,"id":7,"title":"t","body":"b"}"#)
    let post = try await PlaceholderClient(transport: transport).post(id: 7)
    #expect(transport.sent.map(\.path) == ["/api/posts/7"])
    #expect(post.body == "b")
  }

  @Test func aTodoIsPostedWithItsFields() async throws {
    let transport = RecordingStaylyTransport(answer: #"{"userId":2,"id":201,"title":"stay","completed":false}"#)
    let todo = try await PlaceholderClient(transport: transport).addTodo(userId: 2, title: "stay", completed: false)
    #expect(transport.sent.first?.method == "POST")
    #expect(transport.sent.first?.path == "/api/todos")
    #expect(transport.sent.first?.body?.contains(#""userId":2"#) == true)
    #expect(transport.sent.first?.body?.contains(#""title":"stay""#) == true)
    #expect(todo.id == 201)
  }
}

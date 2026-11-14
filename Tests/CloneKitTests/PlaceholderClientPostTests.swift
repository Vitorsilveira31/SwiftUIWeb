import Foundation
import Testing
@testable import CloneKit

private final class PostWritingTransport: PlaceholderTransport, @unchecked Sendable {
  var sent: [(method: String, path: String, body: String?)] = []
  let answer: String

  init(answer: String) { self.answer = answer }

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    sent.append((method, path, body.flatMap { String(data: $0, encoding: .utf8) }))
    return Data(answer.utf8)
  }
}

struct PlaceholderClientPostTests {
  @Test func aPostIsSentAsJSONAndComesBackWithItsId() async throws {
    let transport = PostWritingTransport(answer: #"{"userId":1,"id":101,"title":"t","body":"b"}"#)
    let post = try await PlaceholderClient(transport: transport).createPost(userId: 1, title: "t", body: "b")
    #expect(post.id == 101)
    #expect(transport.sent.first?.method == "POST")
    #expect(transport.sent.first?.path == "/api/posts")
    #expect(transport.sent.first?.body?.contains("\"body\":\"b\"") == true)
  }
}

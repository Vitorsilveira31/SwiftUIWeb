import Foundation
import Testing
@testable import CloneKit

private final class RecordingTransport: PlaceholderTransport, @unchecked Sendable {
  var sent: [(method: String, path: String, body: String?)] = []
  let answer: String

  init(answer: String) { self.answer = answer }

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    sent.append((method, path, body.flatMap { String(data: $0, encoding: .utf8) }))
    return Data(answer.utf8)
  }
}

struct PlaceholderClientTests {
  @Test func postsAreRequestedPageByPage() async throws {
    let transport = RecordingTransport(answer: #"[{"userId":1,"id":3,"title":"t","body":"b"}]"#)
    let posts = try await PlaceholderClient(transport: transport).posts(page: 2, limit: 12)
    #expect(transport.sent.map(\.path) == ["/api/posts?_page=2&_limit=12"])
    #expect(posts.first?.id == 3)
  }

  @Test func aSearchIsEncodedIntoTheQuery() async throws {
    let transport = RecordingTransport(answer: "[]")
    _ = try await PlaceholderClient(transport: transport).photos(page: 1, limit: 30, search: "quiet harbor & café")
    #expect(transport.sent.first?.path == "/api/photos?_page=1&_limit=30&q=quiet%20harbor%20%26%20caf%C3%A9")
    _ = try await PlaceholderClient(transport: transport).photos(page: 1, limit: 30, search: "")
    #expect(transport.sent.last?.path == "/api/photos?_page=1&_limit=30")
  }

  @Test func aCommentIsPostedAsJSONAndComesBackWithItsId() async throws {
    let transport = RecordingTransport(answer: #"{"postId":4,"id":501,"name":"Ana","email":"a@example.test","body":"hi"}"#)
    let comment = try await PlaceholderClient(transport: transport).addComment(postId: 4, name: "Ana", email: "a@example.test", body: "hi")
    #expect(transport.sent.first?.method == "POST")
    #expect(transport.sent.first?.path == "/api/comments")
    #expect(transport.sent.first?.body?.contains(#""postId":4"#) == true)
    #expect(comment.id == 501)
  }

  @Test func nestedRoutesUseTheResourceThatOwnsThem() async throws {
    let transport = RecordingTransport(answer: "[]")
    let client = PlaceholderClient(transport: transport)
    _ = try await client.comments(postId: 7)
    _ = try await client.albums(userId: 2)
    _ = try await client.photos(albumId: 5, limit: 9)
    _ = try await client.posts(userId: 3)
    #expect(transport.sent.map(\.path) == ["/api/posts/7/comments", "/api/users/2/albums", "/api/albums/5/photos?_limit=9", "/api/users/3/posts"])
  }

  @Test func aUserDecodesWithItsAddressAndCompany() throws {
    let json = #"{"id":1,"name":"Ana Alves","username":"AnaAlves","email":"a@example.test","address":{"street":"Harbor Lane","suite":"Apt. 1","city":"Lisbon","zipcode":"11111","geo":{"lat":"1","lng":"2"}},"phone":"+1","website":"w","company":{"name":"Paper Kite","catchPhrase":"c","bs":"b"}}"#
    let user = try JSONDecoder().decode(PlaceholderUser.self, from: Data(json.utf8))
    #expect(user.address.city == "Lisbon")
    #expect(user.company.name == "Paper Kite")
  }

  @Test func picturesPointAtTheMockService() {
    #expect(PlaceholderImage.photo(12, width: 600, height: 400) == "/api/images/photo/12.svg?w=600&h=400")
    #expect(PlaceholderImage.avatar(3) == "/api/images/avatar/3.svg?size=128")
    #expect(PlaceholderImage.thumbnail(9) == "/api/images/thumb/9.svg")
  }
}

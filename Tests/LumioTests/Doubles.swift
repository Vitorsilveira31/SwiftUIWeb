import Foundation
@testable import CloneKit
@testable import Lumio

let ana = LumioUser(id: 1, name: "Ana Alves", username: "AnaAlves", avatarURL: "/a.svg", city: "Lisbon", bio: "bio")
let bruno = LumioUser(id: 2, name: "Bruno Barros", username: "BrunoBarr", avatarURL: "/b.svg", city: "Porto", bio: "bio")

func post(_ id: Int, by author: LumioUser = ana) -> LumioPost {
  LumioPost(id: id, author: author, imageURL: "/p\(id).svg", caption: "caption \(id)", likes: 10, commentCount: 5)
}

struct Failure: Error {}

/// Answers each page with the posts the test gave for it, or fails.
final class StubFeed: LoadFeedUseCase, LoadStoriesUseCase, @unchecked Sendable {
  var pages: [Int: [LumioPost]]
  var people: [LumioUser]
  var fails = false
  private(set) var requested: [Int] = []

  init(pages: [Int: [LumioPost]] = [:], people: [LumioUser] = [ana, bruno]) {
    self.pages = pages
    self.people = people
  }

  func execute(page: Int) async throws -> [LumioPost] {
    requested.append(page)
    if fails { throw Failure() }
    return pages[page] ?? []
  }

  func execute() async throws -> [LumioUser] {
    if fails { throw Failure() }
    return people
  }
}

final class StubComments: LoadCommentsUseCase, AddCommentUseCase, @unchecked Sendable {
  var comments: [LumioComment] = []
  var fails = false
  private(set) var sent: [String] = []

  func execute(postID: Int) async throws -> [LumioComment] {
    if fails { throw Failure() }
    return comments
  }

  func execute(postID: Int, text: String) async throws -> LumioComment {
    if fails { throw Failure() }
    sent.append(text)
    return LumioComment(id: 100 + sent.count, author: "you", text: text)
  }
}

final class StubExplore: LoadExploreUseCase, @unchecked Sendable {
  var tiles: [Int: [LumioTile]] = [:]
  private(set) var searches: [String] = []

  func execute(page: Int, search: String) async throws -> [LumioTile] {
    searches.append("\(page):\(search)")
    return tiles[page] ?? []
  }
}

func tiles(_ count: Int, from start: Int = 1) -> [LumioTile] {
  (start..<(start + count)).map { LumioTile(id: $0, imageURL: "/t\($0).svg", title: "t\($0)") }
}

/// Answers by path, so the repositories can be tested against what the API sends.
struct StubTransport: PlaceholderTransport {
  let answers: [String: String]

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    guard let answer = answers[path] else { throw PlaceholderError.status(404) }
    return Data(answer.utf8)
  }
}

import Foundation
@testable import CloneKit
@testable import Quill

let ana = QuillUser(id: 1, name: "Ana Alves", handle: "@AnaAlves", avatarURL: "/a.svg")
let bruno = QuillUser(id: 2, name: "Bruno Barros", handle: "@BrunoBarr", avatarURL: "/b.svg")

func post(_ id: Int, by author: QuillUser = ana, likes: Int = 10, replies: Int = 5) -> QuillPost {
  QuillPost(id: id, author: author, text: "post \(id)", likes: likes, reposts: 2, replies: replies)
}

struct Failure: Error {}

/// Keeps what a closure gave it, so a test can see what a view model handed over.
final class Recorder<Value>: @unchecked Sendable {
  var values: [Value] = []
}

/// Answers each page of each feed with the posts the test gave for it, keeps what was published, or fails.
final class StubTimeline: LoadTimelineUseCase, PublishPostUseCase, @unchecked Sendable {
  var pages: [QuillFeed: [Int: [QuillPost]]] = [:]
  var fails = false
  var publishFails = false
  private(set) var requested: [String] = []
  private(set) var published: [String] = []

  func execute(feed: QuillFeed, page: Int) async throws -> [QuillPost] {
    requested.append((feed == .forYou ? "forYou" : "following") + ":\(page)")
    if fails { throw Failure() }
    return pages[feed]?[page] ?? []
  }

  func execute(text: String) async throws -> QuillPost {
    if publishFails { throw Failure() }
    published.append(text)
    return post(100 + published.count, by: ana)
  }
}

/// The replies of a thread: what it has, what was written, and whether it fails.
final class StubThread: LoadRepliesUseCase, AddReplyUseCase, @unchecked Sendable {
  var replies: [QuillReply] = []
  var fails = false
  private(set) var sent: [String] = []

  func execute(postID: Int) async throws -> [QuillReply] {
    if fails { throw Failure() }
    return replies
  }

  func execute(postID: Int, text: String) async throws -> QuillReply {
    if fails { throw Failure() }
    sent.append(text)
    return QuillReply(id: 100 + sent.count, name: "you", text: text, avatarURL: "/y.svg")
  }
}

final class StubWhoToFollow: LoadWhoToFollowUseCase, @unchecked Sendable {
  var people: [QuillUser] = [bruno]
  var fails = false

  func execute() async throws -> [QuillUser] {
    if fails { throw Failure() }
    return people
  }
}

final class StubTrends: LoadTrendsUseCase, @unchecked Sendable {
  var trends: [QuillTrend] = []
  var fails = false

  func execute() async throws -> [QuillTrend] {
    if fails { throw Failure() }
    return trends
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

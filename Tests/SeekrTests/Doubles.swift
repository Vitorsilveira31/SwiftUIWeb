import Foundation
import CloneKit
@testable import Seekr

struct Failure: Error {}

func result(_ id: Int, site: String = "anaalves.example.test") -> SeekrResult {
  SeekrResult(id: id, title: "Harbor \(id)", site: site, link: "https://\(site)/posts/\(id)", snippet: "Harbor lights \(id)")
}

func results(_ count: Int, from start: Int = 1) -> [SeekrResult] {
  (start..<(start + count)).map { result($0) }
}

/// Answers a web search with the page the test gave for it, and the total; records what it was asked; or fails.
final class StubSearch: SearchWebUseCase, @unchecked Sendable {
  var pages: [Int: [SeekrResult]] = [:]
  var total = 0
  var fails = false
  private(set) var requested: [String] = []

  func execute(query: String, page: Int) async throws -> SeekrResultPage {
    requested.append("\(query):\(page)")
    if fails { throw Failure() }
    return SeekrResultPage(results: pages[page] ?? [], total: total)
  }
}

/// The same answer for the News tab.
final class StubNews: SearchNewsUseCase, @unchecked Sendable {
  var pages: [Int: [SeekrResult]] = [:]
  var total = 0
  private(set) var requested: [String] = []

  func execute(query: String, page: Int) async throws -> SeekrResultPage {
    requested.append("\(query):\(page)")
    return SeekrResultPage(results: pages[page] ?? [], total: total)
  }
}

final class StubQuestions: LoadQuestionsUseCase, @unchecked Sendable {
  var questions: [String] = []
  private(set) var asked: [String] = []

  func execute(query: String) async throws -> [String] {
    asked.append(query)
    return questions
  }
}

final class StubPictures: SearchPicturesUseCase, @unchecked Sendable {
  var pages: [Int: [SeekrPicture]] = [:]
  var fails = false
  private(set) var requested: [String] = []

  func execute(query: String, page: Int) async throws -> [SeekrPicture] {
    requested.append("\(query):\(page)")
    if fails { throw Failure() }
    return pages[page] ?? []
  }
}

final class StubSuggestions: LoadSuggestionsUseCase, @unchecked Sendable {
  var answers: [String: [String]] = [:]

  func execute(prefix: String) async throws -> [String] { answers[prefix] ?? [] }
}

final class StubLucky: FeelingLuckyUseCase, @unchecked Sendable {
  var link: String?
  var fails = false

  func execute(query: String) async throws -> String? {
    if fails { throw Failure() }
    return link
  }
}

func picture(_ id: Int) -> SeekrPicture {
  SeekrPicture(id: id, title: "Picture \(id)", thumbnailURL: "/t\(id).svg", imageURL: "/p\(id).svg")
}

/// Answers by path, so the repositories can be tested against what the API sends.
struct StubTransport: PlaceholderTransport {
  let answers: [String: String]

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    guard let answer = answers[path] else { throw PlaceholderError.status(404) }
    return Data(answer.utf8)
  }
}

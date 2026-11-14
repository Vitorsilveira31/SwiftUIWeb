import Foundation
@testable import CloneKit
@testable import Neighborly

let ana = NeighborlyUser(id: 1, name: "Ana Alves", username: "AnaAlves", avatarURL: "/a.svg", city: "Lisbon", bio: "bio")
let bruno = NeighborlyUser(id: 2, name: "Bruno Barros", username: "BrunoBarr", avatarURL: "/b.svg", city: "Porto", bio: "bio")
let carla = NeighborlyUser(id: 3, name: "Carla Campos", username: "CarlaCamp", avatarURL: "/c.svg", city: "Lisbon", bio: "bio")

func post(_ id: Int, by author: NeighborlyUser = ana, image: String? = nil) -> NeighborlyPost {
  NeighborlyPost(id: id, author: author, text: "post \(id)", imageURL: image, reactions: 10, commentCount: 5)
}

struct Failure: Error {}

/// Answers each page with the posts the test gave for it, and records what was published; or fails.
final class StubFeed: LoadFeedUseCase, PublishPostUseCase, @unchecked Sendable {
  var pages: [Int: [NeighborlyPost]]
  var fails = false
  private(set) var requested: [Int] = []
  private(set) var published: [String] = []

  init(pages: [Int: [NeighborlyPost]] = [:]) { self.pages = pages }

  func execute(page: Int) async throws -> [NeighborlyPost] {
    requested.append(page)
    if fails { throw Failure() }
    return pages[page] ?? []
  }

  func execute(text: String) async throws -> NeighborlyPost {
    if fails { throw Failure() }
    published.append(text)
    return NeighborlyPost(id: 900 + published.count, author: ana, text: text, imageURL: nil, reactions: 0, commentCount: 0)
  }
}

final class StubComments: LoadCommentsUseCase, AddCommentUseCase, @unchecked Sendable {
  var comments: [NeighborlyComment] = []
  var fails = false
  private(set) var loaded: [Int] = []
  private(set) var sent: [String] = []

  func execute(postID: Int) async throws -> [NeighborlyComment] {
    loaded.append(postID)
    if fails { throw Failure() }
    return comments
  }

  func execute(postID: Int, text: String) async throws -> NeighborlyComment {
    if fails { throw Failure() }
    sent.append(text)
    return NeighborlyComment(id: 100 + sent.count, author: ana.name, text: text)
  }
}

final class StubPeople: LoadPeopleUseCase, @unchecked Sendable {
  var people: [NeighborlyUser] = [ana, bruno, carla]
  var fails = false

  func execute() async throws -> [NeighborlyUser] {
    if fails { throw Failure() }
    return people
  }
}

/// Albums by person, and pictures by album.
final class StubPhotos: LoadAlbumsUseCase, LoadPhotosUseCase, @unchecked Sendable {
  var albums: [Int: [NeighborlyAlbum]] = [:]
  var photos: [Int: [NeighborlyPhoto]] = [:]
  var fails = false
  private(set) var requestedPeople: [Int] = []

  func execute(userID: Int) async throws -> [NeighborlyAlbum] {
    requestedPeople.append(userID)
    if fails { throw Failure() }
    return albums[userID] ?? []
  }

  func execute(albumID: Int) async throws -> [NeighborlyPhoto] {
    if fails { throw Failure() }
    return photos[albumID] ?? []
  }
}

final class StubProfiles: LoadProfileUseCase, @unchecked Sendable {
  var profiles: [Int: NeighborlyProfile] = [:]
  var fails = false

  func execute(userID: Int) async throws -> NeighborlyProfile {
    if fails { throw Failure() }
    guard let profile = profiles[userID] else { throw Failure() }
    return profile
  }
}

func photos(_ count: Int, album: Int = 1) -> [NeighborlyPhoto] {
  (1...count).map { NeighborlyPhoto(id: album * 100 + $0, title: "p\($0)", thumbnailURL: "/t\($0).svg", imageURL: "/p\($0).svg") }
}

/// Answers by method and path, so the repositories can be tested against what the API is asked for.
struct StubTransport: PlaceholderTransport {
  let answers: [String: String]

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    guard let answer = answers["\(method) \(path)"] else { throw PlaceholderError.status(404) }
    return Data(answer.utf8)
  }
}

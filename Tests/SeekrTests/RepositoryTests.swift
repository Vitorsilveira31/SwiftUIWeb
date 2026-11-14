import Testing
import CloneKit
@testable import Seekr

struct RepositoryTests {
  private let users = #"[{"id":1,"name":"Ana Alves","username":"AnaAlves","email":"a@x.test","phone":"1","website":"anaalves.example.test","address":{"street":"s","suite":"u","city":"Lisbon","zipcode":"1"},"company":{"name":"c","catchPhrase":"slow harvests","bs":"b"}}]"#
  private let harbor = #"[{"userId":1,"id":4,"title":"Harbor","body":"Harbor lights glow over the water."}]"#

  @Test func aResultHasTheSiteOfItsAuthorAndALink() async throws {
    let transport = StubTransport(answers: [
      "/api/posts?_page=1&_limit=10&q=harbor": harbor,
      "/api/posts?q=harbor": harbor,
      "/api/users": users,
    ])
    let page = try await LiveWebRepository(client: PlaceholderClient(transport: transport)).results(query: "harbor", page: 1)
    #expect(page.total == 1)
    #expect(page.results.map(\.id) == [4])
    #expect(page.results[0].site == "anaalves.example.test")
    #expect(page.results[0].link == "https://anaalves.example.test/posts/4")
    #expect(page.results[0].snippet == "Harbor lights glow over the water.")
  }

  @Test func theNewsAreTheNewestPostsOfTheQuery() async throws {
    let transport = StubTransport(answers: [
      "/api/posts?_sort=id&_order=desc&_page=1&_limit=10&q=harbor": harbor,
      "/api/posts?q=harbor": harbor,
      "/api/users": users,
    ])
    let page = try await LiveWebRepository(client: PlaceholderClient(transport: transport)).news(query: "harbor", page: 1)
    #expect(page.results.map(\.title) == ["Harbor"])
  }

  @Test func theQuestionsArePeopleCommentsOnTheTopResult() async throws {
    let transport = StubTransport(answers: [
      "/api/posts?_page=1&_limit=1&q=harbor": harbor,
      "/api/posts/4/comments": #"[{"postId":4,"id":1,"name":"Eum voluptas ","email":"a@x.test","body":"b"}]"#,
    ])
    let questions = try await LiveWebRepository(client: PlaceholderClient(transport: transport)).questions(query: "harbor")
    #expect(questions == ["Eum voluptas"])
  }

  @Test func aSuggestionBeginsTheWayTheTextBegan() async throws {
    let transport = StubTransport(answers: [
      "/api/posts?_page=1&_limit=30&q=the": #"[{"userId":1,"id":1,"title":"The Quiet Harbor","body":"b"},{"userId":1,"id":2,"title":"Bread","body":"b"},{"userId":1,"id":3,"title":"the quiet harbor","body":"b"},{"userId":1,"id":4,"title":"The Bread","body":"b"}]"#,
    ])
    let titles = try await LiveSuggestionRepository(client: PlaceholderClient(transport: transport)).suggestions(prefix: "the")
    #expect(titles == ["The Quiet Harbor", "the quiet harbor", "The Bread"])
  }

  @Test func aPictureIsTheMockPhotoAndItsThumbnail() async throws {
    let transport = StubTransport(answers: [
      "/api/photos?_page=1&_limit=30&q=harbor": #"[{"albumId":1,"id":7,"title":"harbor 7","url":"/u","thumbnailUrl":"/t"}]"#,
    ])
    let pictures = try await LivePictureRepository(client: PlaceholderClient(transport: transport)).pictures(query: "harbor", page: 1)
    #expect(pictures.first?.imageURL == "/api/images/photo/7.svg?w=900&h=900")
    #expect(pictures.first?.thumbnailURL == "/api/images/thumb/7.svg")
  }
}

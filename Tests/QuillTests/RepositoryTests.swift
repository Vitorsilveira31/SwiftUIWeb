import Testing
@testable import CloneKit
@testable import Quill

struct RepositoryTests {
  private let users = #"[{"id":1,"name":"Ana Alves","username":"AnaAlves","email":"a@x.test","phone":"1","website":"w","address":{"street":"s","suite":"u","city":"Lisbon","zipcode":"1"},"company":{"name":"c","catchPhrase":"slow harvests","bs":"b"}},{"id":2,"name":"Bruno Barros","username":"BrunoBarr","email":"b@x.test","phone":"2","website":"w","address":{"street":"s","suite":"u","city":"Porto","zipcode":"2"},"company":{"name":"c","catchPhrase":"c","bs":"b"}}]"#

  private func timeline(_ answers: [String: String]) -> LiveTimelineRepository {
    LiveTimelineRepository(client: PlaceholderClient(transport: StubTransport(answers: answers)), currentUserID: 1)
  }

  @Test func aPostIsPairedWithItsAuthorAndCountedFromItsId() async throws {
    let repository = timeline([
      "/api/posts?_page=1&_limit=10": #"[{"userId":2,"id":4,"title":"T","body":"B"},{"userId":9,"id":5,"title":"T","body":"B"}]"#,
      "/api/users": users,
    ])
    let posts = try await repository.posts(feed: .forYou, page: 1)
    #expect(posts.map(\.id) == [4])
    #expect(posts[0].author.handle == "@BrunoBarr")
    #expect(posts[0].text == "B")
    #expect(posts[0].likes == (4 * 37) % 240 + 3)
    #expect(posts[0].replies == QuillMapping.repliesPerPost)
  }

  @Test func theFollowingFeedIsTheNewestPostsOfTheFollowedUsersOnOnePage() async throws {
    let repository = timeline([
      "/api/users": users,
      "/api/users/1/posts": #"[{"userId":1,"id":1,"title":"t","body":"b"},{"userId":1,"id":7,"title":"t","body":"b"}]"#,
      "/api/users/2/posts": #"[{"userId":2,"id":4,"title":"t","body":"b"}]"#,
      "/api/users/3/posts": "[]",
    ])
    let posts = try await repository.posts(feed: .following, page: 1)
    #expect(posts.map(\.id) == [7, 4, 1])
    #expect(try await repository.posts(feed: .following, page: 2).isEmpty)
  }

  @Test func aPublishedPostIsWrittenAsTheReaderAndComesBackWithItsId() async throws {
    let repository = timeline([
      "/api/users": users,
      "/api/posts": #"{"userId":1,"id":101,"title":"Hello","body":"Hello world"}"#,
    ])
    let post = try await repository.publish(text: "Hello world")
    #expect(post.id == 101)
    #expect(post.author.handle == "@AnaAlves")
    #expect(post.text == "Hello world")
  }

  @Test func aReplyIsNamedAfterItsWriterAndKeepsItsText() async throws {
    let repository = LiveRepliesRepository(client: PlaceholderClient(transport: StubTransport(answers: [
      "/api/posts/4/comments": #"[{"postId":4,"id":21,"name":"n","email":"Eliseo@gardner.biz","body":"great"}]"#,
    ])))
    let replies = try await repository.replies(postID: 4)
    #expect(replies.map(\.name) == ["Eliseo"])
    #expect(replies.map(\.text) == ["great"])
  }

  @Test func theSidebarSuggestsTheOtherPeopleAndTheTrendsOfTheFirstAlbums() async throws {
    let repository = LiveSidebarRepository(client: PlaceholderClient(transport: StubTransport(answers: [
      "/api/users": users,
      "/api/users/1/albums": #"[{"userId":1,"id":7,"title":"golden trails"},{"userId":1,"id":8,"title":"slow markets"}]"#,
      "/api/users/2/albums": #"[{"userId":2,"id":11,"title":"quiet ferries"}]"#,
    ])), currentUserID: 1)
    let people = try await repository.suggestions()
    #expect(people.map(\.name) == ["Bruno Barros"])
    let trends = try await repository.trends()
    #expect(trends.map(\.topic) == ["golden trails", "slow markets", "quiet ferries"])
  }
}

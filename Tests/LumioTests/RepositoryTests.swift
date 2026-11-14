import Testing
@testable import CloneKit
@testable import Lumio

struct RepositoryTests {
  private let users = #"[{"id":1,"name":"Ana Alves","username":"AnaAlves","email":"a@x.test","phone":"1","website":"w","address":{"street":"s","suite":"u","city":"Lisbon","zipcode":"1"},"company":{"name":"c","catchPhrase":"slow harvests","bs":"b"}}]"#

  @Test func aPostIsPairedWithItsAuthorAndItsPicture() async throws {
    let transport = StubTransport(answers: [
      "/api/posts?_page=1&_limit=6": #"[{"userId":1,"id":4,"title":"T","body":"B"},{"userId":9,"id":5,"title":"T","body":"B"}]"#,
      "/api/users": users,
    ])
    let posts = try await LiveFeedRepository(client: PlaceholderClient(transport: transport)).posts(page: 1)
    #expect(posts.map(\.id) == [4])
    #expect(posts[0].author.username == "AnaAlves")
    #expect(posts[0].author.city == "Lisbon")
    #expect(posts[0].imageURL == "/api/images/photo/4.svg?w=940&h=940")
    #expect(posts[0].caption == "T\nB")
  }

  @Test func theProfileCountsPostsAndShowsTheFirstAlbumsPictures() async throws {
    let transport = StubTransport(answers: [
      "/api/users": users,
      "/api/users/1/posts": #"[{"userId":1,"id":1,"title":"t","body":"b"},{"userId":1,"id":2,"title":"t","body":"b"}]"#,
      "/api/users/1/albums": #"[{"userId":1,"id":7,"title":"golden trails"},{"userId":1,"id":8,"title":"slow markets"}]"#,
      "/api/albums/7/photos?_limit=18": #"[{"albumId":7,"id":301,"title":"p","url":"/u","thumbnailUrl":"/t"}]"#,
    ])
    let profile = try await LiveProfileRepository(client: PlaceholderClient(transport: transport)).profile(userID: 1)
    #expect(profile.postCount == 2)
    #expect(profile.albumTitles == ["golden trails", "slow markets"])
    #expect(profile.tiles.map(\.id) == [301])
    #expect(profile.user.bio == "slow harvests")
  }

  @Test func aCommentShowsTheNameBeforeTheAtSign() async throws {
    let transport = StubTransport(answers: ["/api/posts/3/comments": #"[{"postId":3,"id":1,"name":"n","email":"iris.ibarra@example.test","body":"hello"}]"#])
    let comments = try await LiveCommentsRepository(client: PlaceholderClient(transport: transport)).comments(postID: 3)
    #expect(comments.first?.author == "iris.ibarra")
  }
}

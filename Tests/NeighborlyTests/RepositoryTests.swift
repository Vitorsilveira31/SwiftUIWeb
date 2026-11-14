import CloneKit
import Testing
@testable import Neighborly

struct RepositoryTests {
  private func person(_ id: Int, _ name: String, _ username: String, _ email: String, _ city: String) -> String {
    #"{"id":\#(id),"name":"\#(name)","username":"\#(username)","email":"\#(email)","phone":"1","website":"w","address":{"street":"s","suite":"u","city":"\#(city)","zipcode":"1"},"company":{"name":"c","catchPhrase":"slow harvests","bs":"b"}}"#
  }

  private var one: String { person(1, "Ana Alves", "AnaAlves", "ana@x.test", "Lisbon") }

  private var users: String {
    "[" + [person(1, "Ana Alves", "AnaAlves", "ana@x.test", "Lisbon"), person(2, "Bruno Barros", "BrunoBarr", "bruno@x.test", "Porto"), person(3, "Carla Campos", "CarlaCamp", "carla@x.test", "Lisbon")].joined(separator: ",") + "]"
  }

  @Test func theFeedPairsEachPostWithItsAuthorAndGivesEvenPostsAPicture() async throws {
    let transport = StubTransport(answers: [
      "GET /api/posts?_page=1&_limit=6": #"[{"userId":1,"id":2,"title":"t","body":"b"},{"userId":9,"id":3,"title":"t","body":"b"}]"#,
      "GET /api/users": users,
    ])
    let posts = try await LiveFeedRepository(client: PlaceholderClient(transport: transport), currentUserID: 1).posts(page: 1)
    #expect(posts.map(\.id) == [2])
    #expect(posts[0].author.city == "Lisbon")
    #expect(posts[0].imageURL == "/api/images/photo/2.svg?w=940&h=940")
    #expect(posts[0].reactions == 62)
    #expect(posts[0].commentCount == 5)
  }

  @Test func aNewPostIsWrittenAsTheReaderAndHasNoPicture() async throws {
    let transport = StubTransport(answers: [
      "POST /api/posts": #"{"userId":1,"id":101,"title":"","body":"Hello street"}"#,
      "GET /api/users/1": one,
    ])
    let post = try await LiveFeedRepository(client: PlaceholderClient(transport: transport), currentUserID: 1).publish(text: "Hello street")
    #expect(post.id == 101)
    #expect(post.text == "Hello street")
    #expect(post.author.name == "Ana Alves")
    #expect(post.imageURL == nil)
    #expect(post.reactions == 0)
  }

  @Test func aCommenterIsTheUserWhoHasTheAddress() async throws {
    let transport = StubTransport(answers: [
      "GET /api/posts/3/comments": #"[{"postId":3,"id":1,"name":"n","email":"bruno@x.test","body":"hello"}]"#,
      "GET /api/users": users,
    ])
    let comments = try await LiveCommentsRepository(client: PlaceholderClient(transport: transport), currentUserID: 1).comments(postID: 3)
    #expect(comments.map(\.author) == ["Bruno Barros"])
    #expect(comments[0].text == "hello")
  }

  @Test func aNewCommentIsWrittenAsTheReader() async throws {
    let transport = StubTransport(answers: [
      "GET /api/users/1": one,
      "POST /api/comments": #"{"postId":3,"id":501,"name":"Ana Alves","email":"ana@x.test","body":"hi"}"#,
    ])
    let comment = try await LiveCommentsRepository(client: PlaceholderClient(transport: transport), currentUserID: 1).add(postID: 3, text: "hi")
    #expect(comment.id == 501)
    #expect(comment.author == "Ana Alves")
    #expect(comment.text == "hi")
  }

  @Test func theProfileCountsAndListsFriendsWithoutTheMemberThemself() async throws {
    let transport = StubTransport(answers: [
      "GET /api/users/1": one,
      "GET /api/users/1/posts": #"[{"userId":1,"id":1,"title":"t","body":"b"},{"userId":1,"id":2,"title":"t","body":"b"}]"#,
      "GET /api/users/1/albums": #"[{"userId":1,"id":7,"title":"golden trails"}]"#,
      "GET /api/users": users,
    ])
    let profile = try await LiveProfileRepository(client: PlaceholderClient(transport: transport)).profile(userID: 1)
    #expect(profile.postCount == 2)
    #expect(profile.albumCount == 1)
    #expect(profile.friends.map(\.id) == [2, 3])
    #expect(profile.coverURL == "/api/images/cover/1.svg?w=1500&h=500")
    #expect(profile.user.bio == "slow harvests")
  }

  @Test func albumsHaveCoversAndPicturesHaveThumbnailsAndLargeImages() async throws {
    let transport = StubTransport(answers: [
      "GET /api/users/1/albums": #"[{"userId":1,"id":7,"title":"golden trails"}]"#,
      "GET /api/albums/7/photos?_limit=24": #"[{"albumId":7,"id":301,"title":"p","url":"/u","thumbnailUrl":"/t"}]"#,
    ])
    let repository = LivePhotosRepository(client: PlaceholderClient(transport: transport))
    let albums = try await repository.albums(userID: 1)
    #expect(albums[0].coverURL == "/api/images/cover/7.svg?w=900&h=420")
    let pictures = try await repository.photos(albumID: 7)
    #expect(pictures[0].thumbnailURL == "/api/images/thumb/301.svg")
    #expect(pictures[0].imageURL == "/api/images/photo/301.svg?w=1000&h=1000")
  }

  @Test func thePeopleAreTheUsersOfTheService() async throws {
    let transport = StubTransport(answers: ["GET /api/users": users])
    let people = try await LivePeopleRepository(client: PlaceholderClient(transport: transport)).people()
    #expect(people.map(\.username) == ["AnaAlves", "BrunoBarr", "CarlaCamp"])
  }
}

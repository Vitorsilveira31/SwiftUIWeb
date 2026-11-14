import Testing
@testable import CloneKit
@testable import Mailo

struct RepositoryTests {
  private let users = #"[{"id":1,"name":"Ana Alves","username":"AnaAlves","email":"ana.alves@example.test","phone":"1","website":"w","address":{"street":"s","suite":"u","city":"Lisbon","zipcode":"1"},"company":{"name":"c","catchPhrase":"slow harvests","bs":"b"}},{"id":2,"name":"Bruno Barros","username":"BrunoBarr","email":"bruno.barros@example.test","phone":"1","website":"w","address":{"street":"s","suite":"u","city":"Porto","zipcode":"1"},"company":{"name":"c","catchPhrase":"c","bs":"b"}}]"#

  @Test func aReceivedMessageHasItsUserAsSenderAndItsTitleAsSubject() async throws {
    let transport = StubTransport(answers: [
      "/api/posts?userId_ne=1": #"[{"userId":2,"id":4,"title":"Harbor","body":"First line\nsecond line"},{"userId":2,"id":9,"title":"Later","body":"B"}]"#,
      "/api/users": users,
    ])
    let messages = try await LiveMailboxRepository(client: PlaceholderClient(transport: transport)).messages(scope: .received, search: "")
    #expect(messages.map(\.id) == [9, 4])
    #expect(messages[1].sender == bruno)
    #expect(messages[1].subject == "Harbor")
    #expect(messages[1].preview == "First line second line")
    #expect(messages[1].recipient == nil)
    #expect(!messages[1].isMine)
  }

  @Test func aSentMessageIsTheAccountsPostWithItsRecipient() async throws {
    let transport = StubTransport(answers: [
      "/api/posts?userId=1&q=harbor": #"[{"userId":1,"id":101,"title":"Hi","body":"B","to":"bruno.barros@example.test"}]"#,
      "/api/users": users,
    ])
    let messages = try await LiveMailboxRepository(client: PlaceholderClient(transport: transport)).messages(scope: .sent, search: "harbor")
    #expect(messages.first?.isMine == true)
    #expect(messages.first?.recipient == "bruno.barros@example.test")
  }

  @Test func aDeletedMessageIsRequestedByItsId() async throws {
    let transport = StubTransport(answers: ["/api/posts/4": "{}"])
    try await LiveMailboxRepository(client: PlaceholderClient(transport: transport)).delete(id: 4)
  }

  @Test func repliesAreTheCommentsOfThePost() async throws {
    let transport = StubTransport(answers: [
      "/api/posts/3/comments": #"[{"postId":3,"id":1,"name":"n","email":"iris.ibarra@example.test","body":"hello"}]"#,
    ])
    let replies = try await LiveMessageRepository(client: PlaceholderClient(transport: transport)).replies(messageID: 3)
    #expect(replies.first?.author.name == "iris.ibarra")
    #expect(replies.first?.body == "hello")
  }

  @Test func aSentMessageComesBackWithItsIdAndRecipient() async throws {
    let transport = StubTransport(answers: [
      "/api/posts": #"{"userId":1,"id":101,"title":"Hi","body":"Hello","to":"bruno.barros@example.test"}"#,
    ])
    let sent = try await LiveMessageRepository(client: PlaceholderClient(transport: transport)).send(to: "bruno.barros@example.test", subject: "Hi", body: "Hello")
    #expect(sent.id == 101)
    #expect(sent.sender == MailoAccount.person)
    #expect(sent.recipient == "bruno.barros@example.test")
  }

  @Test func aReplyIsWrittenAsTheAccount() async throws {
    let transport = StubTransport(answers: [
      "/api/comments": #"{"postId":3,"id":501,"name":"Ana Alves","email":"ana.alves@example.test","body":"Thanks"}"#,
    ])
    let reply = try await LiveMessageRepository(client: PlaceholderClient(transport: transport)).reply(messageID: 3, text: "Thanks")
    #expect(reply.id == 501)
    #expect(reply.author == MailoAccount.person)
  }
}

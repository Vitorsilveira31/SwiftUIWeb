import Testing
@testable import CloneKit
@testable import Stayly

struct RepositoryTests {
  private let albums = #"[{"userId":1,"id":3,"title":"Golden Trails"},{"userId":2,"id":4,"title":"Quiet Harbors"}]"#
  private let users = #"[{"id":1,"name":"Ana Alves","username":"AnaAlves","email":"a@x.test","phone":"1","website":"w","address":{"street":"s","suite":"u","city":"Lisbon","zipcode":"1"},"company":{"name":"c","catchPhrase":"slow harvests","bs":"b"}},{"id":2,"name":"Bruno Barros","username":"BrunoBarr","email":"b@x.test","phone":"1","website":"w","address":{"street":"s","suite":"u","city":"Porto","zipcode":"1"},"company":{"name":"c","catchPhrase":"bright tiles","bs":"b"}}]"#

  private func repository(_ answers: [String: String]) -> LiveStaysRepository {
    LiveStaysRepository(client: PlaceholderClient(transport: StubTransport(answers: answers)))
  }

  @Test func anAlbumIsAStayInItsOwnersCityWithItsTerms() async throws {
    let stays = try await repository(["/api/albums": albums, "/api/users": users]).stays()
    #expect(stays.map(\.id) == [3, 4])
    #expect(stays[0].title == "Golden Trails")
    #expect(stays[0].city == "Lisbon")
    #expect(stays[0].hostID == 1)
    #expect(stays[0].coverURL == "/api/images/photo/101.svg?w=640&h=420")
    #expect(stays[0].pricePerNight == StayTerms.price(3))
    #expect(stays[1].city == "Porto")
  }

  @Test func theDetailHasThePhotosTheDescriptionAndTheHost() async throws {
    let answers = [
      "/api/albums": albums,
      "/api/users": users,
      "/api/albums/3/photos?_limit=12": #"[{"albumId":3,"id":101,"title":"dawn","url":"/u","thumbnailUrl":"/t"}]"#,
      "/api/posts/3": #"{"userId":1,"id":3,"title":"t","body":"A quiet room by the water."}"#,
    ]
    let found = try await repository(answers).detail(stayID: 3)
    #expect(found.stay.id == 3)
    #expect(found.description == "A quiet room by the water.")
    #expect(found.host.name == "Ana Alves")
    #expect(found.host.bio == "slow harvests")
    #expect(found.photos.map(\.id) == [101])
    #expect(found.photos[0].largeURL == "/api/images/photo/101.svg?w=1200&h=800")
    #expect(found.photos[0].thumbnailURL == "/api/images/thumb/101.svg")
    #expect(found.amenities == StayTerms.amenities(3))
  }

  @Test func aStayThatDoesNotExistIsNotFound() async {
    let answers = ["/api/albums": albums, "/api/users": users]
    await #expect(throws: PlaceholderError.self) {
      _ = try await repository(answers).detail(stayID: 99)
    }
  }

  @Test func aReservationIsRecordedAsATodoOfTheHost() async throws {
    let stay = Stay(id: 3, title: "Golden Trails", city: "Lisbon", hostID: 1, coverURL: "/c", pricePerNight: 120, ratingTenths: 40, capacity: 4)
    let checkIn = StayDays.date(day: startDay)
    let checkOut = StayDays.date(day: startDay + 3)
    let client = PlaceholderClient(transport: StubTransport(answers: ["/api/todos": #"{"userId":1,"id":201,"title":"x","completed":false}"#]))
    let reservation = try await LiveReservationsRepository(client: client).reserve(stay: stay, checkIn: checkIn, checkOut: checkOut, guests: 2)
    #expect(reservation.id == 201)
    #expect(reservation.nights == 3)
    #expect(reservation.total == 360)
  }
}

import CloneKit
import Foundation
@testable import Stayly

let host = StayHost(id: 1, name: "Ana Alves", avatarURL: "/a.svg", city: "Lisbon", bio: "bio")

func stay(_ id: Int, city: String = "Lisbon", price: Int = 100, rating: Int = 40, capacity: Int = 4) -> Stay {
  Stay(id: id, title: "Stay \(id)", city: city, hostID: 1, coverURL: "/c\(id).svg", pricePerNight: price, ratingTenths: rating, capacity: capacity)
}

/// Day 20 000 (2024-10-04), the day every test starts from.
let startDay = 20_000

func search(destination: String = "", nights: Int = 2, guests: Int = 2) -> StaySearch {
  StaySearch(destination: destination, checkIn: StayDays.date(day: startDay), checkOut: StayDays.date(day: startDay + nights), guests: guests)
}

struct Failure: Error {}

/// One double for the three use cases of Stayly, so a test can script the stays, a page and the reservations.
final class StubStays: LoadStaysUseCase, LoadStayDetailUseCase, ReserveStayUseCase, @unchecked Sendable {
  var stays: [Stay] = []
  var detail: StayDetail?
  var fails = false
  private(set) var reservations = 0

  func execute() async throws -> [Stay] {
    if fails { throw Failure() }
    return stays
  }

  func execute(stayID: Int) async throws -> StayDetail {
    if fails { throw Failure() }
    guard let detail else { throw Failure() }
    return detail
  }

  func execute(stay: Stay, checkIn: Date, checkOut: Date, guests: Int) async throws -> StayReservation {
    if fails { throw Failure() }
    reservations += 1
    return StayReservation(id: 500 + reservations, stay: stay, checkIn: checkIn, checkOut: checkOut, guests: guests)
  }
}

func detail(_ stay: Stay, photos: Int = 3) -> StayDetail {
  StayDetail(
    stay: stay,
    host: host,
    description: "A quiet room by the water.",
    photos: (1...photos).map { StayPhoto(id: $0, largeURL: "/l\($0).svg", thumbnailURL: "/t\($0).svg", title: "photo \($0)") },
    amenities: [.wifi, .kitchen]
  )
}

/// Answers by path, so the repositories can be tested against what the API sends.
struct StubTransport: PlaceholderTransport {
  let answers: [String: String]

  func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    guard let answer = answers[path] else { throw PlaceholderError.status(404) }
    return Data(answer.utf8)
  }
}

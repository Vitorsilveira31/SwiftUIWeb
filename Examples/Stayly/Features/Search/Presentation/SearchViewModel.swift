import SwiftUIWeb

/// The search form: the city, the two dates and the guests, with the cities the stays are in. Check-out is always after check-in.
@MainActor @Observable
final class SearchViewModel {
  static let guestRange = 1 ... 8

  /// The city the reader picked; empty is anywhere.
  var destination = ""
  private(set) var checkIn: Date
  private(set) var checkOut: Date
  private(set) var guests: Int
  private(set) var destinations: [String] = []
  private(set) var state: LoadState = .loading
  private let load: any LoadStaysUseCase

  init(load: any LoadStaysUseCase, today: Date) {
    self.load = load
    let start = StaySearch.starting(on: today)
    checkIn = start.checkIn
    checkOut = start.checkOut
    guests = start.guests
  }

  var nights: Int { StayDays.nights(from: checkIn, to: checkOut) }

  /// What the form asks for now.
  var stayQuery: StaySearch {
    StaySearch(destination: destination, checkIn: checkIn, checkOut: checkOut, guests: guests)
  }

  func setCheckIn(_ date: Date) {
    let day = StayDays.number(date)
    checkIn = StayDays.date(day: day)
    if StayDays.number(checkOut) <= day { checkOut = StayDays.date(day: day + 1) }
  }

  func setCheckOut(_ date: Date) {
    checkOut = StayDays.date(day: max(StayDays.number(date), StayDays.number(checkIn) + 1))
  }

  func setGuests(_ count: Int) {
    guests = min(max(count, SearchViewModel.guestRange.lowerBound), SearchViewModel.guestRange.upperBound)
  }

  /// The cities of the stays, A to Z, for the destination picker.
  func loadDestinations() async {
    state = .loading
    do {
      let stays = try await load.execute()
      destinations = Array(Set(stays.map(\.city))).sorted()
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }
}

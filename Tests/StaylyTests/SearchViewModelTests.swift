import Testing
@testable import Stayly

@MainActor
struct SearchViewModelTests {
  private func make(_ stays: StubStays = StubStays()) -> SearchViewModel {
    SearchViewModel(load: stays, today: StayDays.date(day: startDay))
  }

  @Test func theFormStartsTwoNightsFromTodayForTwoGuestsAnywhere() {
    let model = make()
    #expect(model.nights == 2)
    #expect(model.guests == 2)
    #expect(model.stayQuery.destination.isEmpty)
    #expect(StayDays.number(model.checkIn) == startDay)
  }

  @Test func checkInMovedPastCheckOutKeepsAtLeastOneNight() {
    let model = make()
    model.setCheckIn(StayDays.date(day: startDay + 5))
    #expect(StayDays.number(model.checkOut) == startDay + 6)
    #expect(model.nights == 1)
  }

  @Test func checkOutBeforeCheckInIsMovedAfterIt() {
    let model = make()
    model.setCheckOut(StayDays.date(day: startDay - 3))
    #expect(model.nights == 1)
    #expect(StayDays.number(model.checkOut) == startDay + 1)
  }

  @Test func guestsStayBetweenOneAndEight() {
    let model = make()
    model.setGuests(20)
    #expect(model.guests == 8)
    model.setGuests(0)
    #expect(model.guests == 1)
  }

  @Test func theDestinationsAreTheCitiesOfTheStaysInOrder() async {
    let stays = StubStays()
    stays.stays = [stay(1, city: "Porto"), stay(2, city: "Lisbon"), stay(3, city: "Porto")]
    let model = make(stays)
    await model.loadDestinations()
    #expect(model.state == .loaded)
    #expect(model.destinations == ["Lisbon", "Porto"])
  }

  @Test func aFailedLoadSaysSo() async {
    let stays = StubStays()
    stays.fails = true
    let model = make(stays)
    await model.loadDestinations()
    #expect(model.state == .failed(FailureText.unreachable))
  }
}

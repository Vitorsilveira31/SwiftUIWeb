import Testing
@testable import Stayly

@MainActor
struct ResultsViewModelTests {
  private func make(_ stays: StubStays, query: StaySearch = search(destination: "Lisbon")) -> ResultsViewModel {
    ResultsViewModel(query: query, load: stays)
  }

  @Test func theResultsAreTheStaysOfTheSearchesCity() async {
    let stays = StubStays()
    stays.stays = [stay(1, city: "Lisbon"), stay(2, city: "Porto"), stay(3, city: "Lisbon")]
    let model = make(stays)
    #expect(model.state == .loading)
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.visible.map(\.id) == [1, 3])
    #expect(model.query.nights == 2)
  }

  @Test func aFailedLoadSaysSoAndTryingAgainRecovers() async {
    let stays = StubStays()
    stays.stays = [stay(1)]
    stays.fails = true
    let model = make(stays)
    await model.load()
    #expect(model.state == .failed(FailureText.unreachable))
    stays.fails = false
    await model.load()
    #expect(model.visible.map(\.id) == [1])
  }

  @Test func thePriceRangeNeverCrosses() async {
    let model = make(StubStays(), query: search())
    model.setMinPrice(250)
    #expect(model.filter.minPrice == 250)
    model.setMinPrice(StayFilter.priceCeiling + 50)
    #expect(model.filter.minPrice == StayFilter.priceCeiling)
    model.setMaxPrice(90)
    #expect(model.filter.maxPrice == model.filter.minPrice)
    model.setMinPrice(StayFilter.priceFloor - 10)
    #expect(model.filter.minPrice == StayFilter.priceFloor)
  }

  @Test func theRatingAndTheOrderAreTheReadersChoice() async {
    let stays = StubStays()
    stays.stays = [stay(1, price: 100, rating: 30), stay(2, price: 200, rating: 45)]
    let model = make(stays, query: search())
    await model.load()
    model.setMinRating(40)
    #expect(model.visible.map(\.id) == [2])
    model.setMinRating(0)
    model.setSort(.priceHighToLow)
    #expect(model.visible.map(\.id) == [2, 1])
  }
}

import Testing
@testable import Stayly

struct StayFilterTests {
  private let stays = [
    stay(1, city: "Lisbon", price: 100, rating: 40, capacity: 2),
    stay(2, city: "Porto", price: 200, rating: 45, capacity: 4),
    stay(3, city: "Lisbon", price: 300, rating: 30, capacity: 6),
  ]

  @Test func aCityAndGuestsKeepOnlyTheStaysThatFit() {
    let filter = StayFilter(search: search(destination: "Lisbon", guests: 3))
    #expect(filter.apply(to: stays).map(\.id) == [3])
  }

  @Test func anywhereKeepsEveryCity() {
    #expect(StayFilter(search: search(guests: 1)).apply(to: stays).map(\.id) == [1, 2, 3])
  }

  @Test func thePriceRangeAndTheMinimumRatingNarrowTheList() {
    var filter = StayFilter(search: search(guests: 1))
    filter.maxPrice = 200
    #expect(filter.apply(to: stays).map(\.id) == [1, 2])
    filter.minPrice = 150
    #expect(filter.apply(to: stays).map(\.id) == [2])
    filter.minPrice = StayFilter.priceFloor
    filter.minRatingTenths = 40
    #expect(filter.apply(to: stays).map(\.id) == [1, 2])
  }

  @Test func theSortOrdersByPriceOrRatingWithTiesByID() {
    var filter = StayFilter(search: search(guests: 1))
    filter.sort = .priceLowToHigh
    #expect(filter.apply(to: stays).map(\.id) == [1, 2, 3])
    filter.sort = .priceHighToLow
    #expect(filter.apply(to: stays).map(\.id) == [3, 2, 1])
    filter.sort = .topRated
    #expect(filter.apply(to: stays).map(\.id) == [2, 1, 3])
    let tied = [stay(9, price: 100), stay(4, price: 100)]
    filter.sort = .priceLowToHigh
    #expect(filter.apply(to: tied).map(\.id) == [4, 9])
  }
}

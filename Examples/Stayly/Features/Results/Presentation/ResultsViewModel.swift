import SwiftUIWeb

/// The results of a search: the stays, loaded once, and the filters and order the reader chose. Filtering is local, so a change is immediate.
@MainActor @Observable
final class ResultsViewModel {
  /// The search these results answer.
  let query: StaySearch
  private(set) var stays: [Stay] = []
  private(set) var state: LoadState = .loading
  private(set) var filter: StayFilter
  private let loader: any LoadStaysUseCase

  init(query: StaySearch, load: any LoadStaysUseCase) {
    self.query = query
    loader = load
    filter = StayFilter(search: query)
  }

  /// The stays that match the filters, in the order chosen.
  var visible: [Stay] { filter.apply(to: stays) }

  func load() async {
    state = .loading
    do {
      stays = try await loader.execute()
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }

  /// The lowest price shown; it never passes the highest.
  func setMinPrice(_ price: Int) {
    filter.minPrice = min(max(price, StayFilter.priceFloor), filter.maxPrice)
  }

  /// The highest price shown; it never goes below the lowest.
  func setMaxPrice(_ price: Int) {
    filter.maxPrice = max(min(price, StayFilter.priceCeiling), filter.minPrice)
  }

  func setMinRating(_ tenths: Int) { filter.minRatingTenths = tenths }

  func setSort(_ order: StaySort) { filter.sort = order }
}

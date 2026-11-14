/// The words of the results: the list, the filters and the order.
enum ResultsStrings {
  static let allStays = "All stays"
  static let changeSearch = "Change search"
  static let filters = "Filters"
  static let showStays = "Show stays"
  static let loading = "Loading stays…"
  static let failedTitle = "Stays could not load"
  static let retry = "Try again"
  static let noMatches = "No stays match these filters. Widen the price range or lower the rating."
  static let priceTitle = "Price per night"
  static let ratingTitle = "Minimum rating"
  static let anyRating = "Any rating"
  static let sortTitle = "Sort by"

  static func title(_ city: String) -> String { city.isEmpty ? allStays : "Stays in \(city)" }

  static func dates(_ checkIn: String, _ checkOut: String) -> String { "\(checkIn) – \(checkOut)" }

  static func found(_ count: Int) -> String { count == 1 ? "1 stay found" : "\(count) stays found" }

  static func priceFrom(_ price: Int) -> String { "From \(StayFormat.price(price))" }

  static func priceUpTo(_ price: Int) -> String { "Up to \(StayFormat.price(price))" }

  static func ratingAtLeast(_ tenths: Int) -> String { "\(StayFormat.rating(tenths)) and up" }

  static func sort(_ order: StaySort) -> String {
    switch order {
    case .recommended: return "Recommended"
    case .priceLowToHigh: return "Price: low to high"
    case .priceHighToLow: return "Price: high to low"
    case .topRated: return "Top rated"
    }
  }
}

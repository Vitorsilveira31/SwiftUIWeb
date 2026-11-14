/// The filters and the order of the results: the city, the guests the stay must hold, the price per night and the minimum rating.
struct StayFilter: Hashable {
  static let priceFloor = 60
  static let priceCeiling = 300

  var destination: String
  var guests: Int
  var minPrice = StayFilter.priceFloor
  var maxPrice = StayFilter.priceCeiling
  /// In tenths: 0 keeps every rating, 45 keeps only stays rated 4.5 and up.
  var minRatingTenths = 0
  var sort = StaySort.recommended

  init(search: StaySearch) {
    destination = search.destination
    guests = search.guests
  }

  func matches(_ stay: Stay) -> Bool {
    (destination.isEmpty || stay.city == destination)
      && stay.capacity >= guests
      && stay.pricePerNight >= minPrice
      && stay.pricePerNight <= maxPrice
      && stay.ratingTenths >= minRatingTenths
  }

  /// The stays that match, in the order chosen. Ties keep the order of the ids, so the list does not shuffle.
  func apply(to stays: [Stay]) -> [Stay] {
    let matching = stays.filter { matches($0) }
    switch sort {
    case .recommended:
      return matching
    case .priceLowToHigh:
      return matching.sorted { $0.pricePerNight == $1.pricePerNight ? $0.id < $1.id : $0.pricePerNight < $1.pricePerNight }
    case .priceHighToLow:
      return matching.sorted { $0.pricePerNight == $1.pricePerNight ? $0.id < $1.id : $0.pricePerNight > $1.pricePerNight }
    case .topRated:
      return matching.sorted { $0.ratingTenths == $1.ratingTenths ? $0.id < $1.id : $0.ratingTenths > $1.ratingTenths }
    }
  }
}

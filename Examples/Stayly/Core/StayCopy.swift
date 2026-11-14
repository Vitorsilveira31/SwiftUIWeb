/// The words that several screens of Stayly show (a card, the booking panel, the trips), in one place so they read the same everywhere.
enum StayCopy {
  static let save = "Save stay"
  static let unsave = "Remove from saved"

  static func nights(_ count: Int) -> String { count == 1 ? "1 night" : "\(count) nights" }

  static func guests(_ count: Int) -> String { count == 1 ? "1 guest" : "\(count) guests" }

  static func perNight(_ price: Int) -> String { "\(StayFormat.price(price)) per night" }

  static func totalFor(_ amount: Int, nights count: Int) -> String { "\(StayFormat.price(amount)) total for \(nights(count))" }

  static func rating(_ tenths: Int) -> String { "Rated \(StayFormat.rating(tenths)) out of 5" }
}

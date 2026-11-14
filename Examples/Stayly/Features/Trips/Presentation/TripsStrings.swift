/// The words of the trips: the reservations made in this session.
enum TripsStrings {
  static let title = "My trips"
  static let empty = "No trips yet. Reserve a stay and it will appear here."
  static let reserved = "Reserved"

  static func dates(_ checkIn: String, _ checkOut: String) -> String { "\(checkIn) – \(checkOut)" }
}

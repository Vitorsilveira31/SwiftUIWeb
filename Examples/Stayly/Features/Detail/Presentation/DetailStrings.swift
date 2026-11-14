/// The words of a stay's page and its booking panel.
enum DetailStrings {
  static let back = "Back to results"
  static let loading = "Loading the stay…"
  static let failedTitle = "This stay could not load"
  static let retry = "Try again"
  static let about = "About this stay"
  static let offers = "What this place offers"
  static let checkIn = "Check-in"
  static let checkOut = "Check-out"
  static let guests = "Guests"
  static let reserve = "Reserve"
  static let reserving = "Reserving…"
  static let reserveFailed = "The reservation could not be made. Try again."
  static let confirmedTitle = "Reservation confirmed"
  static let confirmedText = "Your stay is in My trips."

  static func hostedBy(_ name: String) -> String { "Hosted by \(name)" }

  static func livesIn(_ city: String) -> String { "Lives in \(city)" }

  static func showPhoto(_ title: String) -> String { "Show photo: \(title)" }

  static func amenity(_ amenity: StayAmenity) -> String {
    switch amenity {
    case .wifi: return "Wi-Fi"
    case .kitchen: return "Kitchen"
    case .pool: return "Pool"
    case .parking: return "Free parking"
    case .seaView: return "Sea view"
    case .airConditioning: return "Air conditioning"
    }
  }
}

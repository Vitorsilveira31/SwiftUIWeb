/// What a stay offers. The words for each are in the detail page's strings.
enum StayAmenity: Hashable {
  case wifi
  case kitchen
  case pool
  case parking
  case seaView
  case airConditioning

  static let all: [StayAmenity] = [.wifi, .kitchen, .pool, .parking, .seaView, .airConditioning]
}

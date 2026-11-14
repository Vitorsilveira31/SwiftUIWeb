/// A stay as its page shows it: the pictures, the description from its post, what it offers and who hosts it.
struct StayDetail: Hashable {
  let stay: Stay
  let host: StayHost
  let description: String
  let photos: [StayPhoto]
  let amenities: [StayAmenity]
}

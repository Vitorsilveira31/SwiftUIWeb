/// A stay: an album of pictures in a city, offered by its host, with a price per night and a rating.
struct Stay: Identifiable, Hashable {
  let id: Int
  let title: String
  let city: String
  let hostID: Int
  let coverURL: String
  let pricePerNight: Int
  /// In tenths of a point (45 is 4.5), so a rating needs no decimal formatting.
  let ratingTenths: Int
  /// How many guests it holds.
  let capacity: Int
}

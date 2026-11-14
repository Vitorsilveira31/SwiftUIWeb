/// The terms of a stay that the API does not send, derived from the album's number so every run shows the same stays: the price per
/// night, the rating, how many guests it holds, what it offers and the picture it opens with.
enum StayTerms {
  /// jsonplaceholder numbers the photos in order, fifty to an album: album 1 has photos 1 to 50, album 2 has 51 to 100.
  static let photosPerAlbum = 50

  /// Wrapping arithmetic on the magnitude: album ids come from the server, and Int is 32 bits in the browser build.
  static func coverPhotoID(albumID: Int) -> Int {
    Int(truncatingIfNeeded: (albumID.magnitude &- 1) &* UInt(photosPerAlbum) &+ 1)
  }

  /// Between 60 and 299 dollars.
  static func price(_ albumID: Int) -> Int { 60 + Int((albumID.magnitude &* 37) % 240) }

  /// Between 3.0 and 5.0, in tenths.
  static func ratingTenths(_ albumID: Int) -> Int { 30 + Int((albumID.magnitude &* 13) % 21) }

  /// Between two and six guests.
  static func capacity(_ albumID: Int) -> Int { 2 + Int(albumID.magnitude % 5) }

  /// The price of a whole stay, or nil when it does not fit in an Int (a check-out in a far-off year).
  static func total(perNight price: Int, nights: Int) -> Int? {
    let (product, overflow) = price.multipliedReportingOverflow(by: nights)
    return overflow ? nil : product
  }

  /// Most of the amenities, a few left out, chosen by the number; never none (the one at `albumID` modulo six is always there).
  static func amenities(_ albumID: Int) -> [StayAmenity] {
    var offered: [StayAmenity] = []
    let featured = Int(albumID.magnitude % UInt(StayAmenity.all.count))
    for (index, amenity) in StayAmenity.all.enumerated() where index == featured || (albumID.magnitude &* UInt(index + 3)) % 4 != 0 {
      offered.append(amenity)
    }
    return offered
  }
}

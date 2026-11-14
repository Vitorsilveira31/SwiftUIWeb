import CloneKit

/// Stays from the API. An album is a stay; its owner is the host and their address the city; a stay's description is the body of the
/// post with the same number. The rest (price, rating, capacity, amenities) comes from `StayTerms`.
struct LiveStaysRepository: StaysRepository {
  let client: PlaceholderClient

  func stays() async throws -> [Stay] {
    async let albums = client.albums()
    async let users = client.users()
    let (allAlbums, owners) = try await (albums, users)
    // One index per load: scanning every owner for each album is quadratic.
    let ownersByID = Dictionary(owners.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return allAlbums.compactMap { album in
      guard let owner = ownersByID[album.userId] else { return nil }
      return stay(album, owner: owner)
    }
  }

  func detail(stayID: Int) async throws -> StayDetail {
    async let albums = client.albums()
    async let users = client.users()
    async let photos = client.photos(albumId: stayID, limit: 12)
    async let post = client.post(id: stayID)
    let (allAlbums, owners, stayPhotos, description) = try await (albums, users, photos, post)
    guard let album = allAlbums.first(where: { $0.id == stayID }), let owner = owners.first(where: { $0.id == album.userId }) else {
      throw PlaceholderError.status(404)
    }
    return StayDetail(
      stay: stay(album, owner: owner),
      host: StayHost(
        id: owner.id,
        name: owner.name,
        avatarURL: PlaceholderImage.avatar(owner.id, size: 256),
        city: owner.address.city,
        bio: owner.company.catchPhrase
      ),
      description: description.body,
      photos: stayPhotos.map { StayPhoto(id: $0.id, largeURL: PlaceholderImage.photo($0.id, width: 1_200, height: 800), thumbnailURL: PlaceholderImage.thumbnail($0.id), title: $0.title) },
      amenities: StayTerms.amenities(stayID)
    )
  }

  private func stay(_ album: PlaceholderAlbum, owner: PlaceholderUser) -> Stay {
    Stay(
      id: album.id,
      title: album.title,
      city: owner.address.city,
      hostID: owner.id,
      coverURL: PlaceholderImage.photo(StayTerms.coverPhotoID(albumID: album.id), width: 640, height: 420),
      pricePerNight: StayTerms.price(album.id),
      ratingTenths: StayTerms.ratingTenths(album.id),
      capacity: StayTerms.capacity(album.id)
    )
  }
}

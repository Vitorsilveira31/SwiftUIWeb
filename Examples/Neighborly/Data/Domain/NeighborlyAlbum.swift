/// An album of pictures, with a wide picture to show it by.
struct NeighborlyAlbum: Identifiable, Hashable {
  let id: Int
  let title: String
  let coverURL: String
}

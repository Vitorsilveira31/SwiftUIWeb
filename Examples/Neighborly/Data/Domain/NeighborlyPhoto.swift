/// A picture in an album: a small one for the grid and a large one for the viewer.
struct NeighborlyPhoto: Identifiable, Hashable {
  let id: Int
  let title: String
  let thumbnailURL: String
  let imageURL: String
}

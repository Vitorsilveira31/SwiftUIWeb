/// One picture of a stay: the large one for the gallery and the small one for its strip of thumbnails.
struct StayPhoto: Identifiable, Hashable {
  let id: Int
  let largeURL: String
  let thumbnailURL: String
  let title: String
}

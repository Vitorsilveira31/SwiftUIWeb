/// A picture of the Images tab: its thumbnail in the grid, the large one in the preview.
struct SeekrPicture: Identifiable, Hashable {
  let id: Int
  let title: String
  let thumbnailURL: String
  let imageURL: String
}

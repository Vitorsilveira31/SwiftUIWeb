/// Where the pictures of the Images tab come from.
protocol PictureRepository: Sendable {
  func pictures(query: String, page: Int) async throws -> [SeekrPicture]
}

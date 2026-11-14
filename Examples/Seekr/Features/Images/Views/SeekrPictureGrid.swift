import SwiftUIWeb

/// The pictures of the search as a grid of squares; a click opens the picture in the preview.
struct SeekrPictureGrid: View {
  let viewModel: SeekrImagesViewModel

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: SeekrLayout.tileMinimum), spacing: 8)], spacing: 8) {
      ForEach(viewModel.pictures) { picture in
        Button { viewModel.select(picture) } label: {
          SeekrPictureTile(picture: picture)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

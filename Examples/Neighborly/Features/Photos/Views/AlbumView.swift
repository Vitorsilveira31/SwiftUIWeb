import SwiftUIWeb

/// An album open: its pictures as a grid, or, once one is picked, that picture larger. Back returns to the albums.
struct AlbumView: View {
  let viewModel: AlbumViewModel
  let close: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Button(PhotosStrings.back, action: close).buttonStyle(.bordered)
        Text(viewModel.album.title).font(.headline).lineLimit(1)
        Spacer()
      }
      if let photo = viewModel.selected {
        PhotoViewer(viewModel: viewModel, photo: photo)
      } else {
        PictureGrid(viewModel: viewModel)
      }
    }
  }
}

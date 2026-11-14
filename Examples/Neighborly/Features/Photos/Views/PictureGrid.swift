import SwiftUIWeb

/// The pictures of the album open, as squares in a grid; a spinner or the failure while they load.
struct PictureGrid: View {
  let viewModel: AlbumViewModel

  var body: some View {
    if viewModel.state == .loaded {
      if viewModel.photos.isEmpty {
        Text(PhotosStrings.noPictures).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 32)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: NeighborlyLayout.gridSpacing)], spacing: NeighborlyLayout.gridSpacing) {
          ForEach(viewModel.photos) { photo in
            PhotoTile(photo: photo) { viewModel.select(photo) }
          }
        }
      }
    } else {
      NeighborlyStatusView(state: viewModel.state, loading: PhotosStrings.picturesLoading, failedTitle: PhotosStrings.picturesFailed, retry: PhotosStrings.retry) {
        Task { await viewModel.load() }
      }
    }
  }
}

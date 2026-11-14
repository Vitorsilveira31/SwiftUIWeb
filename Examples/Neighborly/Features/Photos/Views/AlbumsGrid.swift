import SwiftUIWeb

/// The albums of the person picked, as covers in a grid; a spinner or the failure while they load.
struct AlbumsGrid: View {
  let viewModel: PhotosViewModel

  var body: some View {
    if viewModel.state == .loaded {
      if viewModel.albums.isEmpty {
        Text(PhotosStrings.noAlbums).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 32)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
          ForEach(viewModel.albums) { album in
            AlbumCard(album: album) { viewModel.openAlbum(album) }
          }
        }
      }
    } else {
      NeighborlyStatusView(state: viewModel.state, loading: PhotosStrings.albumsLoading, failedTitle: PhotosStrings.albumsFailed, retry: PhotosStrings.retry) {
        Task { await viewModel.load() }
      }
    }
  }
}

import SwiftUIWeb

/// The Images tab: the preview of the picture chosen, then the grid of the search's pictures. Loading, failed and empty states replace
/// the grid.
struct SeekrImagesView: View {
  let viewModel: SeekrImagesViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let picture = viewModel.selected {
        SeekrPreviewPanel(picture: picture) { viewModel.select(nil) }
      }
      if viewModel.state != .loaded {
        SeekrStatusView(state: viewModel.state, loading: ImagesStrings.loading, failedTitle: ImagesStrings.failedTitle, retry: ImagesStrings.retry) {
          Task { await viewModel.run(viewModel.query) }
        }
      } else if viewModel.pictures.isEmpty {
        Text(ImagesStrings.noPictures(viewModel.query)).foregroundStyle(.secondary).padding(.vertical, 32)
      } else {
        SeekrPictureGrid(viewModel: viewModel)
        if !viewModel.reachedEnd {
          HStack {
            Spacer()
            if viewModel.isLoadingMore {
              ProgressView()
            } else {
              Button(ImagesStrings.more) { Task { await viewModel.loadMore() } }.buttonStyle(.bordered)
            }
            Spacer()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

import SwiftUIWeb

/// One picture larger, with its title, the way back to the grid and the pictures before and after it.
struct PhotoViewer: View {
  let viewModel: AlbumViewModel
  let photo: NeighborlyPhoto

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        Button(PhotosStrings.allPictures) { viewModel.select(nil) }.buttonStyle(.bordered)
        Spacer()
        Button(PhotosStrings.previous) { viewModel.step(-1) }.buttonStyle(.bordered)
        Button(PhotosStrings.next) { viewModel.step(1) }.buttonStyle(.bordered)
      }
      Image(photo.imageURL, alt: photo.title)
        .resizable()
        .scaledToFit()
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 640)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      Text(photo.title).font(.callout).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }
}

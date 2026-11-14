import SwiftUIWeb

/// A square of the grid: a small picture, and a tap that shows it larger.
struct PhotoTile: View {
  let photo: NeighborlyPhoto
  let onOpen: @MainActor @Sendable () -> Void

  var body: some View {
    Button(action: onOpen) {
      Image(photo.thumbnailURL, alt: photo.title)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
    .buttonStyle(.plain)
    .accessibilityLabel(PhotosStrings.showPicture(photo.title))
  }
}

import SwiftUIWeb

/// An album as a card: its wide cover and its title; a tap opens it.
struct AlbumCard: View {
  let album: NeighborlyAlbum
  let onOpen: @MainActor @Sendable () -> Void

  var body: some View {
    Button(action: onOpen) {
      VStack(alignment: .leading, spacing: 6) {
        Image(album.coverURL, alt: album.title)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .aspectRatio(1.6, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 10))
        Text(album.title).fontWeight(.semibold).lineLimit(1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(PhotosStrings.openAlbum(album.title))
  }
}

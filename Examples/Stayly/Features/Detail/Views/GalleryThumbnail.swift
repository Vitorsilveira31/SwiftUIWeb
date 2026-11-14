import SwiftUIWeb

/// One picture of the strip. The one on show has the brand outline.
struct GalleryThumbnail: View {
  let photo: StayPhoto
  let selected: Bool
  let action: @MainActor @Sendable () -> Void

  var body: some View {
    Button(action: action) {
      Image(photo.thumbnailURL, alt: photo.title)
        .resizable()
        .scaledToFill()
        .frame(width: StaylyLayout.thumbnailSize, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(selected ? StaylyPalette.teal : Color.white, lineWidth: 3) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(DetailStrings.showPhoto(photo.title))
  }
}

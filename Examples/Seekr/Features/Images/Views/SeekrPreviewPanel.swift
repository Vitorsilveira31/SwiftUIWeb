import SwiftUIWeb

/// The preview of the picture chosen: the large picture, its title and number, and a way to close it.
struct SeekrPreviewPanel: View {
  let picture: SeekrPicture
  let close: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(picture.imageURL, alt: picture.title)
        .resizable()
        .scaledToFill()
        .frame(width: SeekrLayout.previewWidth, height: SeekrLayout.previewWidth)
        .clipped()
      Text(picture.title).font(.headline)
      Text(ImagesStrings.number(picture.id)).font(.caption).foregroundStyle(.secondary)
      Button(ImagesStrings.close, action: close).buttonStyle(.bordered)
    }
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

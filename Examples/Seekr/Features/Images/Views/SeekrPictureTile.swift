import SwiftUIWeb

/// One square of the picture grid: the thumbnail of the picture.
struct SeekrPictureTile: View {
  let picture: SeekrPicture

  var body: some View {
    Image(picture.thumbnailURL, alt: picture.title)
      .resizable()
      .scaledToFill()
      .frame(maxWidth: .infinity)
      .aspectRatio(1, contentMode: .fit)
      .clipped()
  }
}

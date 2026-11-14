import SwiftUIWeb

/// The large picture of the stay, and a strip of thumbnails under it; a thumbnail shows its picture large.
struct StayGallery: View {
  let photos: [StayPhoto]
  let fallbackURL: String
  let index: Int
  let select: @MainActor @Sendable (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if photos.indices.contains(index) {
        Image(photos[index].largeURL, alt: photos[index].title)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .frame(height: 420)
          .clipShape(RoundedRectangle(cornerRadius: StaylyLayout.cardRadius))
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 10) {
            ForEach(photos.indices, id: \.self) { position in
              GalleryThumbnail(photo: photos[position], selected: position == index) { select(position) }
            }
          }
        }
      } else {
        Image(fallbackURL, alt: "")
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .frame(height: 420)
          .clipShape(RoundedRectangle(cornerRadius: StaylyLayout.cardRadius))
      }
    }
  }
}

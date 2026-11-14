import SwiftUIWeb

/// What a stay is: the gallery, the host, the description from its post and what it offers.
struct DetailInfo: View {
  let viewModel: DetailViewModel
  let detail: StayDetail

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      StayGallery(photos: detail.photos, fallbackURL: detail.stay.coverURL, index: viewModel.photoIndex) { position in
        viewModel.select(photo: position)
      }
      HostRow(host: detail.host)
      Divider()
      VStack(alignment: .leading, spacing: 8) {
        Text(DetailStrings.about).font(.headline)
        Text(detail.description)
      }
      Divider()
      AmenityList(amenities: detail.amenities)
    }
  }
}

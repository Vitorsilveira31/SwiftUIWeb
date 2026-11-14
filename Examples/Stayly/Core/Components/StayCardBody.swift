import SwiftUIWeb

/// The picture and the facts of a stay card: its title, city, rating, price per night and, when the dates are known, the total.
struct StayCardBody: View {
  let stay: Stay
  var nights: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(stay.coverURL, alt: stay.title)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .frame(height: StaylyLayout.cardPictureHeight)
        .clipped()
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .top, spacing: 8) {
          Text(stay.title).font(.headline).lineLimit(1)
          Spacer()
          StayRatingBadge(tenths: stay.ratingTenths)
        }
        Text(stay.city).foregroundStyle(.secondary)
        Text(StayCopy.perNight(stay.pricePerNight)).fontWeight(.semibold)
        if let nights, let total = StayTerms.total(perNight: stay.pricePerNight, nights: nights) {
          Text(StayCopy.totalFor(total, nights: nights)).font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

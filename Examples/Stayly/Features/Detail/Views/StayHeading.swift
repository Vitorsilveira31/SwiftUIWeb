import SwiftUIWeb

/// The title of a stay, its city and its rating.
struct StayHeading: View {
  let stay: Stay

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(stay.title).font(.largeTitle).fontWeight(.bold)
      HStack(spacing: 12) {
        Text(stay.city).foregroundStyle(.secondary)
        StayRatingBadge(tenths: stay.ratingTenths)
      }
    }
  }
}

import SwiftUIWeb

/// A star and the rating, in tenths shown as a number: "★ 4.5".
struct StayRatingBadge: View {
  let tenths: Int

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "star.fill").foregroundStyle(StaylyPalette.gold)
      Text(StayFormat.rating(tenths)).fontWeight(.semibold)
    }
    .font(.caption)
    .accessibilityLabel(StayCopy.rating(tenths))
  }
}

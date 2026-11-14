import SwiftUIWeb

/// The group the feed shows, with the way back to everyone.
struct GroupBanner: View {
  let viewModel: FeedViewModel
  let city: String

  var body: some View {
    HStack(spacing: 8) {
      Text(FeedStrings.groupTitle(city)).fontWeight(.semibold)
      Spacer()
      Button(FeedStrings.clearGroup) { viewModel.setGroup(nil) }
        .buttonStyle(.bordered)
    }
    .padding(12)
    .background(NeighborlyPalette.card)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

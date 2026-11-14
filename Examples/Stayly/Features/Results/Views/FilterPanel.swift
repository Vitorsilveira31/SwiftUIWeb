import SwiftUIWeb

/// The filters and the order of the results: the price per night, the minimum rating and the sort.
struct FilterPanel: View {
  let viewModel: ResultsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      PriceFilter(viewModel: viewModel)
      Divider()
      VStack(alignment: .leading, spacing: 8) {
        Picker(ResultsStrings.ratingTitle, selection: Binding(get: { viewModel.filter.minRatingTenths }, set: { viewModel.setMinRating($0) })) {
          Text(ResultsStrings.anyRating).tag(0)
          Text(ResultsStrings.ratingAtLeast(30)).tag(30)
          Text(ResultsStrings.ratingAtLeast(40)).tag(40)
          Text(ResultsStrings.ratingAtLeast(45)).tag(45)
        }
      }
      Divider()
      VStack(alignment: .leading, spacing: 8) {
        Picker(ResultsStrings.sortTitle, selection: Binding(get: { viewModel.filter.sort }, set: { viewModel.setSort($0) })) {
          Text(ResultsStrings.sort(.recommended)).tag(StaySort.recommended)
          Text(ResultsStrings.sort(.priceLowToHigh)).tag(StaySort.priceLowToHigh)
          Text(ResultsStrings.sort(.priceHighToLow)).tag(StaySort.priceHighToLow)
          Text(ResultsStrings.sort(.topRated)).tag(StaySort.topRated)
        }
      }
    }
  }
}

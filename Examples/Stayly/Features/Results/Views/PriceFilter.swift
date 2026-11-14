import SwiftUIWeb

/// The price per night as a range: two sliders, the lowest and the highest, that never cross.
struct PriceFilter: View {
  let viewModel: ResultsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(ResultsStrings.priceTitle).font(.headline)
      Text(ResultsStrings.priceFrom(viewModel.filter.minPrice)).foregroundStyle(.secondary)
      Slider(
        value: Binding(get: { Double(viewModel.filter.minPrice) }, set: { viewModel.setMinPrice(Int($0)) }),
        in: Double(StayFilter.priceFloor) ... Double(StayFilter.priceCeiling),
        step: 5
      )
      Text(ResultsStrings.priceUpTo(viewModel.filter.maxPrice)).foregroundStyle(.secondary)
      Slider(
        value: Binding(get: { Double(viewModel.filter.maxPrice) }, set: { viewModel.setMaxPrice(Int($0)) }),
        in: Double(StayFilter.priceFloor) ... Double(StayFilter.priceCeiling),
        step: 5
      )
    }
  }
}

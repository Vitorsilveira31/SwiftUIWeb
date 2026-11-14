import SwiftUIWeb

/// The way back to the search, what was searched for, and (on a phone) the button that opens the filters.
struct ResultsHeader: View {
  let viewModel: ResultsViewModel
  let showsFilters: Bool
  let back: @MainActor @Sendable () -> Void
  let filters: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button(ResultsStrings.changeSearch, action: back).buttonStyle(.bordered)
        Spacer()
        if showsFilters {
          Button(ResultsStrings.filters, action: filters).buttonStyle(.bordered)
        }
      }
      Text(ResultsStrings.title(viewModel.query.destination)).font(.title2).fontWeight(.bold)
      Text(ResultsStrings.dates(StayFormat.day(viewModel.query.checkIn), StayFormat.day(viewModel.query.checkOut)))
        .foregroundStyle(.secondary)
      Text(StayCopy.nights(viewModel.query.nights)).foregroundStyle(.secondary)
      Text(StayCopy.guests(viewModel.query.guests)).foregroundStyle(.secondary)
    }
  }
}

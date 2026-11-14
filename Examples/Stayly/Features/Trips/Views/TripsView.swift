import SwiftUIWeb

/// My trips: the stays reserved in this session, or the words that say there are none yet.
struct TripsView: View {
  let viewModel: TripsViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(TripsStrings.title).font(.title2).fontWeight(.bold)
        if viewModel.reservations.isEmpty {
          Text(TripsStrings.empty).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 48)
        } else {
          ForEach(viewModel.reservations) { reservation in
            TripRow(reservation: reservation)
          }
        }
      }
      .padding(20)
      .frame(maxWidth: StaylyLayout.resultsWidth)
      .frame(maxWidth: .infinity)
    }
  }
}

import SwiftUIWeb

/// The city to stay in: anywhere, or one of the cities of the stays.
struct DestinationField: View {
  let viewModel: SearchViewModel

  var body: some View {
    Picker(SearchStrings.destination, selection: Binding(get: { viewModel.destination }, set: { viewModel.destination = $0 })) {
      Text(SearchStrings.anywhere).tag("")
      ForEach(viewModel.destinations, id: \.self) { city in
        Text(city).tag(city)
      }
    }
  }
}

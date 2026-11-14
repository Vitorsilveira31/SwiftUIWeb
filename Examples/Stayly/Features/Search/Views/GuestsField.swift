import SwiftUIWeb

/// How many guests: a stepper, between one and eight.
struct GuestsField: View {
  let viewModel: SearchViewModel

  var body: some View {
    Stepper(value: Binding(get: { viewModel.guests }, set: { viewModel.setGuests($0) }), in: SearchViewModel.guestRange) {
      HStack {
        Text(SearchStrings.guests)
        Spacer()
        Text(StayCopy.guests(viewModel.guests)).foregroundStyle(.secondary)
      }
    }
  }
}

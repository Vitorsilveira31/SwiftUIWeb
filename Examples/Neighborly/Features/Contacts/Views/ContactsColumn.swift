import SwiftUIWeb

/// The right column on a wide screen: the people of Neighborly, each one a way to their profile.
struct ContactsColumn: View {
  let viewModel: ContactsViewModel
  let openPerson: @MainActor @Sendable (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(ContactsStrings.title).font(.headline)
      if viewModel.state == .loaded {
        ForEach(viewModel.people) { person in
          ContactRow(user: person, openPerson: openPerson)
        }
      } else {
        NeighborlyStatusView(state: viewModel.state, loading: ContactsStrings.loading, failedTitle: ContactsStrings.failedTitle, retry: ContactsStrings.retry, padding: 24) {
          Task { await viewModel.load() }
        }
      }
      Spacer()
    }
    .padding(14)
  }
}

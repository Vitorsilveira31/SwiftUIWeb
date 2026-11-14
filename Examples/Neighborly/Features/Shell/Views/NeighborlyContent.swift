import SwiftUIWeb

/// The screen on the tab shown; the same screen in the middle column on a wide screen and above the bottom bar on a phone.
struct NeighborlyContent: View {
  let shell: ShellViewModel

  var body: some View {
    Group {
      switch shell.tab {
      case .home:
        FeedView(viewModel: shell.feed) { id in shell.openPerson(id) }
      case .photos:
        PhotosView(viewModel: shell.photos, contacts: shell.contacts)
      case .profile:
        ProfileView(viewModel: shell.profile) { id in shell.openPerson(id) }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

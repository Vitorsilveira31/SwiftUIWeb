import SwiftUIWeb

/// The bottom bar on a phone: Home, Photos and your profile.
struct NeighborlyBottomBar: View {
  let shell: ShellViewModel

  var body: some View {
    HStack(spacing: 0) {
      BottomBarItem(title: ShellStrings.home, symbol: "house", selected: shell.tab == .home) { shell.goHome() }
      BottomBarItem(title: ShellStrings.photos, symbol: "photo.on.rectangle", selected: shell.tab == .photos) { shell.showPhotos() }
      BottomBarItem(title: ShellStrings.profile, symbol: "person.crop.circle", selected: shell.tab == .profile) { shell.openPerson(shell.currentUserID) }
    }
    .padding(.vertical, 6)
    .background(NeighborlyPalette.card)
    .overlay(alignment: .top) { Rectangle().fill(NeighborlyPalette.line).frame(height: 1) }
  }
}

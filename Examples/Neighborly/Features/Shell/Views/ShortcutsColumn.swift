import SwiftUIWeb

/// The left column on a wide screen: shortcuts to Home, your friends and the albums, and one group for each city of neighbors.
struct ShortcutsColumn: View {
  let shell: ShellViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(ShellStrings.shortcuts).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
      ShortcutRow(title: ShellStrings.home, symbol: "house") { shell.goHome() }
      ShortcutRow(title: ShellStrings.friends, symbol: "person.2") { shell.openPerson(shell.currentUserID) }
      ShortcutRow(title: ShellStrings.albums, symbol: "photo.on.rectangle") { shell.showPhotos() }
      Text(ShellStrings.groups).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).padding(.top, 14)
      ForEach(shell.contacts.cities, id: \.self) { city in
        ShortcutRow(title: FeedStrings.groupTitle(city), symbol: "person.3") { shell.showGroup(city) }
      }
      Spacer()
    }
    .padding(14)
  }
}

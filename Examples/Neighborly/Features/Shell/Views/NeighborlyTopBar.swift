import SwiftUIWeb

/// The brand: the mark and the name, and the way to your own profile.
struct NeighborlyTopBar: View {
  let shell: ShellViewModel

  var body: some View {
    HStack(spacing: 10) {
      NeighborlyLogo(size: 34)
      VStack(alignment: .leading, spacing: 0) {
        Text(ShellStrings.appName).font(.title3).fontWeight(.bold)
        Text(ShellStrings.tagline).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        shell.openPerson(shell.currentUserID)
      } label: {
        Image(systemName: "person.crop.circle").font(.title2)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(ShellStrings.yourProfile)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

import SwiftUIWeb

/// The brand: the mark, the name and the tagline.
struct StaylyTopBar: View {
  var body: some View {
    HStack(spacing: 10) {
      StaylyLogo(size: 30)
      Text(ShellStrings.appName).font(.title3).fontWeight(.bold)
      Text(ShellStrings.tagline).font(.caption).foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

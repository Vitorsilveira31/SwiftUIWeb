import SwiftUIWeb

/// The brand: the mark and the name.
struct LumioTopBar: View {
  var body: some View {
    HStack(spacing: 10) {
      LumioLogo(size: 30)
      Text(ShellStrings.appName).font(.title3).fontWeight(.bold)
      Text(ShellStrings.tagline).font(.caption).foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

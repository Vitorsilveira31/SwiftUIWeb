import SwiftUIWeb

/// The mark and the name of the site.
struct SiteBrandView: View {
  let language: SiteLanguage

  var body: some View {
    HStack(spacing: 10) {
      Text("S")
        .font(.headline)
        .fontWeight(.heavy)
        .foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background(SiteTheme.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        Text(ShellStrings.siteName).font(.headline)
        Text(ShellStrings.tagline(language)).font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

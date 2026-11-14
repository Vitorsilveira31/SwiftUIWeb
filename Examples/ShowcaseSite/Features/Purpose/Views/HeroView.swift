import SwiftUIWeb

/// The first thing a visitor reads: the promise, one sentence behind it and where to go next.
struct HeroView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(PurposeStrings.eyebrow(language))
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(SiteTheme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(SiteTheme.accent.opacity(0.12))
        .clipShape(Capsule())
      VStack(alignment: .leading, spacing: 0) {
        Text(PurposeStrings.headline(language)).foregroundStyle(.primary)
        Text(PurposeStrings.headlineAccent(language)).foregroundStyle(SiteTheme.accentGradient)
      }
      .font(.system(size: 44, weight: .bold, design: .rounded))
      .accessibilityAddTraits(.isHeader)
      SiteParagraph(text: PurposeStrings.lead(language), isLead: true)
      HeroActions()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 8)
  }
}

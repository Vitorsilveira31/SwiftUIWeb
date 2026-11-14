import SwiftUIWeb

/// The home page: what SwiftUIWeb is, a live example, and where it fits and where it does not yet.
struct PurposeView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageScaffold(width: SiteLayout.wideWidth) {
      HeroView()
      HeroDemoView()
      PurposeSection(
        heading: PurposeStrings.fitsHeading(language),
        items: PurposeStrings.fits(language),
        symbol: "checkmark.circle",
        tint: SiteTheme.positive
      )
      PurposeSection(
        heading: PurposeStrings.limitsHeading(language),
        items: PurposeStrings.limits(language),
        symbol: "info.circle",
        tint: SiteTheme.negative
      )
    }
  }
}

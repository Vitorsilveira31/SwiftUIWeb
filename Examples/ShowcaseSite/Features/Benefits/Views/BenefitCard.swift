import SwiftUIWeb

/// One benefit: a badge, a statement and the sentence behind it.
struct BenefitCard: View {
  let benefit: BenefitVO

  var body: some View {
    SiteIconRow(symbol: benefit.symbol, tint: SiteTheme.accent, title: benefit.title, detail: benefit.detail)
  }
}

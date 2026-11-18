import SwiftUIWeb

/// A card with a badge, a short bold statement and the sentence that backs it. It fills the height of its cell, so the cards
/// of a row end together whatever their text.
struct SiteIconRow: View {
  let symbol: String
  let tint: Color
  let title: String
  let detail: String

  var body: some View {
    SiteCard(fillsHeight: true) {
      SiteIconBadge(symbol: symbol, tint: tint)
      SiteBulletRow(title: title, detail: detail)
    }
  }
}

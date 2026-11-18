import SwiftUIWeb

/// A titled list of claims, each on a card with a symbol: the item's own, or the section's.
struct PurposeSection: View {
  let heading: String
  let items: [PurposeItemVO]
  var symbol = "info.circle"
  var tint: Color = SiteTheme.accent
  var minimumWidth: CGFloat = SiteLayout.cardMinWidth

  var body: some View {
    SiteSection(heading: heading) {
      SiteCardGrid(minimumWidth: minimumWidth) {
        ForEach(items, id: \.id) { item in
          SiteIconRow(symbol: item.symbol ?? symbol, tint: tint, title: item.title, detail: item.detail)
        }
      }
    }
  }
}

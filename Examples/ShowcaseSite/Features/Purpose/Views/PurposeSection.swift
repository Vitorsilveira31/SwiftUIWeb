import SwiftUIWeb

/// A titled list of claims, each on a card with its own symbol.
struct PurposeSection: View {
  let heading: String
  let items: [PurposeItemVO]
  var symbol = "info.circle"
  var tint: Color = SiteTheme.accent

  var body: some View {
    SiteSection(heading: heading) {
      SiteCardGrid {
        ForEach(items, id: \.id) { item in
          SiteIconRow(symbol: symbol, tint: tint, title: item.title, detail: item.detail)
        }
      }
    }
  }
}

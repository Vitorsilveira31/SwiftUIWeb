import SwiftUIWeb

/// A titled list of claims, each on a card with its own symbol.
struct PurposeSection: View {
  let heading: String
  let items: [PurposeItemVO]
  var symbol = "info.circle"
  var tint: Color = SiteTheme.accent

  var body: some View {
    VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
      SiteHeading(text: heading)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
        ForEach(items, id: \.id) { item in
          SiteIconRow(symbol: symbol, tint: tint, title: item.title, detail: item.detail)
        }
      }
    }
  }
}

import SwiftUIWeb

/// A symbol on a soft, tinted square: the mark of a card, so cards read at a glance.
struct SiteIconBadge: View {
  let symbol: String
  var tint: Color = SiteTheme.accent

  var body: some View {
    Image(systemName: symbol)
      .font(.headline)
      .foregroundStyle(tint)
      .frame(width: 36, height: 36)
      .background(tint.opacity(0.14))
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .accessibilityHidden(true)
  }
}

import SwiftUIWeb

/// A bordered surface for a group of related content. With `fillsHeight` the surface takes the height it is offered, its
/// content at the top: in a grid, the cards of a row then end together whatever their text. (The frame sits inside the
/// background, so the background is as tall as the frame; outside it, as in SwiftUI, the frame would grow and the surface
/// would keep its content's height.)
struct SiteCard<Content: View>: View {
  let fillsHeight: Bool
  let content: Content

  init(fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
    self.fillsHeight = fillsHeight
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) { content }
      .padding(SiteLayout.cardPadding)
      .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
      .background(Color.primary.opacity(0.04))
      .clipShape(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius))
      .overlay(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius).stroke(Color.primary.opacity(0.12)))
  }
}

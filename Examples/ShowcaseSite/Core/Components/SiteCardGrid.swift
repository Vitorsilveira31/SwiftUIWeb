import SwiftUIWeb

/// Cards in as many columns as fit, each at least `minimumWidth` wide, `gridSpacing` apart across and down.
struct SiteCardGrid<Content: View>: View {
  var minimumWidth: CGFloat = SiteLayout.cardMinWidth
  let content: Content

  init(minimumWidth: CGFloat = SiteLayout.cardMinWidth, @ViewBuilder content: () -> Content) {
    self.minimumWidth = minimumWidth
    self.content = content()
  }

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: SiteLayout.gridSpacing)],
      alignment: .leading,
      spacing: SiteLayout.gridSpacing
    ) { content }
  }
}

import SwiftUIWeb

/// One page: a single vertical scroller with a centered reading column.
struct SitePageScaffold<Content: View>: View {
  let width: CGFloat
  let content: Content

  init(width: CGFloat = SiteLayout.readingWidth, @ViewBuilder content: () -> Content) {
    self.width = width
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: SiteLayout.sectionSpacing) { content }
        .frame(maxWidth: width, alignment: .leading)
        .padding(.horizontal, SiteLayout.gutter)
        .padding(.vertical, SiteLayout.sectionSpacing)
        .frame(maxWidth: .infinity)
    }
  }
}

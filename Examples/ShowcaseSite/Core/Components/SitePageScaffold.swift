import SwiftUIWeb

/// One page: a single vertical scroller with the site's content column (`SitePageFrame`), its sections `sectionSpacing`
/// apart.
struct SitePageScaffold<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ScrollView {
      SitePageFrame {
        VStack(alignment: .leading, spacing: SiteLayout.sectionSpacing) { content }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.vertical, SiteLayout.pageInset)
    }
  }
}

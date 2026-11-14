import SwiftUIWeb

/// A bordered surface for a group of related content.
struct SiteCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) { content }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.primary.opacity(0.04))
      .clipShape(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius))
      .overlay(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius).stroke(Color.primary.opacity(0.12)))
  }
}

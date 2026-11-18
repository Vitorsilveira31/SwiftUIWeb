import SwiftUIWeb

/// A paragraph of body text; `isLead` sets the larger text a page opens with. A line is never longer than
/// `SiteLayout.readingWidth`, so text stays readable in the full column.
struct SiteParagraph: View {
  let text: String
  var isLead = false

  var body: some View {
    Text(text)
      .font(isLead ? .title3 : .body)
      .foregroundStyle(isLead ? .primary : .secondary)
      .lineSpacing(4)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: SiteLayout.readingWidth, alignment: .leading)
  }
}

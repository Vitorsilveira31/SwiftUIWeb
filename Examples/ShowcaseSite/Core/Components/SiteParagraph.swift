import SwiftUIWeb

/// A paragraph of body text; `isLead` sets the larger text a page opens with.
struct SiteParagraph: View {
  let text: String
  var isLead = false

  var body: some View {
    Text(text)
      .font(isLead ? .title3 : .body)
      .foregroundStyle(isLead ? .primary : .secondary)
      .lineSpacing(4)
      .fixedSize(horizontal: false, vertical: true)
  }
}

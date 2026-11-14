import SwiftUIWeb

/// Source code in a monospaced block that can be selected and copied.
struct SiteCodeBlock: View {
  let code: String

  var body: some View {
    ScrollView(.horizontal) {
      Text(code)
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .padding(14)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.07))
    .clipShape(RoundedRectangle(cornerRadius: SiteLayout.cornerRadius))
  }
}

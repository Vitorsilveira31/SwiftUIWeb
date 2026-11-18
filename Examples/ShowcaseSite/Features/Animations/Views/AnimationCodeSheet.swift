import SwiftUIWeb

/// The code behind one animation, over the page, with a button that closes it.
struct AnimationCodeSheet: View {
  let demo: AnimationDemoVO
  let doneLabel: String
  /// The animation whose code is open: set to nil to close it.
  @Binding var shown: AnimationDemoVO?

  /// The height the code needs: a line is about 24 points, and the title and the padding add up to about 100. A scroll view has
  /// no height of its own in a sheet that sizes to its content (Safari drew it as a bar), so the sheet is as tall as the lines.
  private var codeHeight: CGFloat {
    CGFloat(demo.code.filter { $0 == "\n" }.count + 1) * 24 + 100
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
      HStack {
        Text(demo.title).font(.title3).fontWeight(.bold)
        Spacer()
        Button(doneLabel) { shown = nil }.buttonStyle(.borderedProminent).tint(SiteTheme.accent)
      }
      SiteCodeBlock(code: demo.code)
    }
    .padding(20)
    .frame(minHeight: codeHeight, alignment: .topLeading)
  }
}

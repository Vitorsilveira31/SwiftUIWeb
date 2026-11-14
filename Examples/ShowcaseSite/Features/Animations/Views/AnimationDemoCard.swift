import SwiftUIWeb

/// One animation: what it is, the live view that plays it, and a button that opens the code that makes it.
struct AnimationDemoCard<Demo: View>: View {
  let demo: AnimationDemoVO
  let codeLabel: String
  let doneLabel: String
  let content: Demo
  @State private var showsCode = false

  /// Every card is this tall (its content's height plus the card's 16-point padding on each side), so the grid that holds
  /// them lays rows out without measuring a card.
  static var height: CGFloat { 376 }
  private static var contentHeight: CGFloat { height - 32 }

  init(demo: AnimationDemoVO, codeLabel: String, doneLabel: String, @ViewBuilder content: () -> Demo) {
    self.demo = demo
    self.codeLabel = codeLabel
    self.doneLabel = doneLabel
    self.content = content()
  }

  /// The height the code needs: a line is about 24 points, and the title and the padding add up to about 100.
  private var codeHeight: CGFloat {
    CGFloat(demo.code.filter { $0 == "\n" }.count + 1) * 24 + 100
  }

  var body: some View {
    SiteCard {
      VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
        VStack(alignment: .leading, spacing: 4) {
          Text(demo.title).font(.headline)
          Text(demo.detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        }
        content
          .frame(maxWidth: .infinity, minHeight: 176)
          .padding(.vertical, 8)
        Spacer(minLength: 0)
        Button { showsCode = true } label: {
          Label(codeLabel, systemImage: "chevron.left.forwardslash.chevron.right")
        }
        .buttonStyle(.bordered)
      }
      .frame(maxWidth: .infinity, minHeight: Self.contentHeight, maxHeight: Self.contentHeight, alignment: .topLeading)
    }
    // The code opens over the page rather than growing the card: the cards share a row, and a taller one would push into
    // the row below.
    .sheet(isPresented: $showsCode) {
      VStack(alignment: .leading, spacing: SiteLayout.blockSpacing) {
        HStack {
          Text(demo.title).font(.title3).fontWeight(.bold)
          Spacer()
          Button(doneLabel) { showsCode = false }.buttonStyle(.borderedProminent)
        }
        SiteCodeBlock(code: demo.code)
      }
      .padding(20)
      // A scroll view has no height of its own in a sheet that sizes to its content (Safari draws it as a bar), so the sheet
      // is as tall as the code's lines.
      .frame(minHeight: codeHeight, alignment: .topLeading)
    }
  }
}

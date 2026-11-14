import SwiftUIWeb

/// One animation: what it is, the live view that plays it, and a button that asks for the code that makes it. The code opens
/// from the page (`AnimationsView`), not from the card: a card is placed by its own offset, which would keep a sheet under the
/// cards drawn after it.
struct AnimationDemoCard<Demo: View>: View {
  let demo: AnimationDemoVO
  let codeLabel: String
  /// The animation whose code is open over the page: the button sets it to this card's.
  @Binding var shownCode: AnimationDemoVO?
  let content: Demo

  /// Every card is this tall (its content's height plus the card's 16-point padding on each side), so the grid that holds
  /// them lays rows out without measuring a card.
  static var height: CGFloat { 376 }
  private static var contentHeight: CGFloat { height - 32 }

  init(demo: AnimationDemoVO, codeLabel: String, shownCode: Binding<AnimationDemoVO?>, @ViewBuilder content: () -> Demo) {
    self.demo = demo
    self.codeLabel = codeLabel
    self._shownCode = shownCode
    self.content = content()
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
        Button { shownCode = demo } label: {
          Label(codeLabel, systemImage: "chevron.left.forwardslash.chevron.right")
        }
        .buttonStyle(.bordered)
      }
      .frame(maxWidth: .infinity, minHeight: Self.contentHeight, maxHeight: Self.contentHeight, alignment: .topLeading)
    }
  }
}

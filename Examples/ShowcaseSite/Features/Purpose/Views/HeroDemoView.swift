import SwiftUIWeb

/// The app the README opens with, as code beside the same code running: the page is itself a SwiftUIWeb app.
///
/// The two are a grid of two columns where they fit and one where they do not. Side by side, the running app's card is as
/// tall as the code beside it (a grid row is as tall as its tallest cell, and the card fills its cell), so the boxes end
/// together.
struct HeroDemoView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SiteCardGrid(minimumWidth: SiteLayout.wideCardMinWidth) {
      code
      live
    }
  }

  private var code: some View {
    VStack(alignment: .leading, spacing: 8) {
      caption(PurposeStrings.demoCode(language))
      SiteCodeBlock(code: HeroDemoView.source)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var live: some View {
    VStack(alignment: .leading, spacing: 8) {
      caption(PurposeStrings.demoLive(language))
      SiteCard(fillsHeight: true) {
        HeroCounterView().frame(maxHeight: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func caption(_ text: String) -> some View {
    Text(text).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
  }

  static let source = """
    struct CounterView: View {
      @State private var count = 0

      var body: some View {
        VStack(spacing: 12) {
          Text("Tapped \\(count) times")
            .font(.title)
          Button("Tap me") { count += 1 }
            .buttonStyle(.borderedProminent)
        }
        .padding()
      }
    }
    """
}

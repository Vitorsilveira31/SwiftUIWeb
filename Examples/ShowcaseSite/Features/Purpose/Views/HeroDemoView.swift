import SwiftUIWeb

/// The app the README opens with, as code beside the same code running: the page is itself a SwiftUIWeb app.
struct HeroDemoView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 14) {
        code
        live
      }
      VStack(alignment: .leading, spacing: 14) {
        code
        live
      }
    }
  }

  private var code: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(PurposeStrings.demoCode(language)).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
      SiteCodeBlock(code: HeroDemoView.source)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var live: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(PurposeStrings.demoLive(language)).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
      SiteCard { HeroCounterView() }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

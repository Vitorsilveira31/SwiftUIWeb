import SwiftUIWeb

/// The counter of `HeroDemoView.source`, running.
struct HeroCounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(spacing: 12) {
      Text("Tapped \(count) times").font(.title)
      Button("Tap me") { count += 1 }
        .buttonStyle(.borderedProminent)
        .tint(SiteTheme.accent)
    }
    .padding()
    .frame(maxWidth: .infinity, minHeight: 120)
  }
}

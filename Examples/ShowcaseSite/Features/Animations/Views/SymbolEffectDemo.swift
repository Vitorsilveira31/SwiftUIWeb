import SwiftUIWeb

/// Symbols that bounce, pulse and swap (`symbolEffect`).
struct SymbolEffectDemo: View {
  @State private var rings = 0
  @State private var listening = false
  @State private var starred = false

  var body: some View {
    VStack(spacing: 14) {
      HStack(spacing: 28) {
        Image(systemName: "bell.fill")
          .symbolEffect(.bounce, value: rings)
        Image(systemName: "wifi")
          .symbolEffect(.pulse, isActive: listening)
        Image(systemName: starred ? "star.fill" : "star")
          .contentTransition(.symbolEffect(.replace))
      }
      .font(.system(size: 34))
      .foregroundStyle(SiteTheme.accent)
      HStack(spacing: 8) {
        Button("Ring") { rings += 1 }
        Button(listening ? "Stop" : "Listen") { listening.toggle() }
        Button("Star") { withAnimation { starred.toggle() } }
      }
      .buttonStyle(.bordered)
    }
  }
}

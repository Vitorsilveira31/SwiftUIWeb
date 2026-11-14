import SwiftUIWeb

/// A view that enters and leaves with the transition picked above it.
struct TransitionsDemo: View {
  @State private var shown = true
  @State private var kind = 0

  private static let kinds: [(String, AnyTransition)] = [
    ("Opacity", .opacity),
    ("Scale", .scale),
    ("Slide", .slide),
    ("Move", .move(edge: .bottom)),
    ("Combined", AnyTransition.move(edge: .leading).combined(with: .opacity)),
  ]

  var body: some View {
    VStack(spacing: 12) {
      ZStack {
        if shown {
          RoundedRectangle(cornerRadius: 14)
            .fill(SiteTheme.accentGradient)
            .frame(width: 132, height: 64)
            .transition(Self.kinds[kind].1)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 84)
      .clipped()
      HStack(spacing: 10) {
        Picker("Transition", selection: $kind) {
          ForEach(0..<Self.kinds.count, id: \.self) { index in Text(Self.kinds[index].0).tag(index) }
        }
        .pickerStyle(.menu)
        Button(shown ? "Hide" : "Show") { withAnimation(.easeInOut(duration: 0.5)) { shown.toggle() } }
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

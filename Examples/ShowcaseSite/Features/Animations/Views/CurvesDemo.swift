import SwiftUIWeb

/// Three dots take the same trip with a different curve each: linear, ease in and out, and a bouncy spring.
struct CurvesDemo: View {
  @State private var arrived = false

  var body: some View {
    VStack(spacing: 10) {
      lane(.linear(duration: 1.2))
      lane(.easeInOut(duration: 1.2))
      lane(.bouncy(duration: 1.2))
      Button("Run") { arrived.toggle() }
        .buttonStyle(.bordered)
    }
  }

  private func lane(_ curve: Animation) -> some View {
    ZStack(alignment: .leading) {
      Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
      Circle()
        .fill(SiteTheme.accent)
        .frame(width: 22, height: 22)
        .offset(x: arrived ? 210 : 0)
        .animation(curve, value: arrived)
    }
    .frame(maxWidth: 240)
  }
}

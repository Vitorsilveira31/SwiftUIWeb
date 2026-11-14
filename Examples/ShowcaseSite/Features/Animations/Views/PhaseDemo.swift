import SwiftUIWeb

/// A heartbeat that steps through its phases again and again (`phaseAnimator`).
struct PhaseDemo: View {
  var body: some View {
    Image(systemName: "heart.fill")
      .font(.system(size: 48))
      .foregroundStyle(SiteTheme.accent)
      .phaseAnimator([1.0, 1.3, 1.0, 1.15]) { content, scale in
        content.scaleEffect(scale)
      } animation: { _ in
        .easeInOut(duration: 0.35)
      }
      .accessibilityLabel("Heartbeat")
  }
}

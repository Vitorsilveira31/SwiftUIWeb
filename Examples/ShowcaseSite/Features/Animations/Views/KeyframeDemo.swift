import SwiftUIWeb

/// The values a jump moves: how far up the ball is and how much it is stretched.
struct JumpValues {
  var lift = 0.0
  var stretch = 1.0
}

/// A ball that jumps along keyframe tracks, one per value, each time the button is pressed (`keyframeAnimator`).
struct KeyframeDemo: View {
  @State private var jumps = 0

  var body: some View {
    VStack(spacing: 16) {
      Circle()
        .fill(SiteTheme.accentGradient)
        .frame(width: 44, height: 44)
        .keyframeAnimator(initialValue: JumpValues(), trigger: jumps) { content, value in
          content.scaleEffect(x: 1 / value.stretch, y: value.stretch).offset(y: value.lift)
        } keyframes: { _ in
          KeyframeTrack(\.lift) {
            CubicKeyframe(-48, duration: 0.3)
            CubicKeyframe(0, duration: 0.3)
          }
          KeyframeTrack(\.stretch) {
            LinearKeyframe(1.25, duration: 0.15)
            LinearKeyframe(0.9, duration: 0.35)
            SpringKeyframe(1, duration: 0.3)
          }
        }
        .frame(height: 100, alignment: .bottom)
      Button("Jump") { jumps += 1 }
        .buttonStyle(.bordered)
    }
  }
}

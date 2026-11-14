import SwiftUI

/// Values the tour animates together; each property has its own keyframe track.
struct TourValues {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation: Double = 0
    var scale: CGFloat = 1
}

/// tour: a 24x24 square with three keyframes (0%, 40%, 100%) over 1.5s, forever.
/// CSS can give each segment its own timing function; KeyframeTrack cannot, so the
/// segments use cubic splines instead of the reference's cubic-bezier and ease-out.
struct TourTile: View {
    var body: some View {
        KeyframeAnimator(initialValue: TourValues(), repeating: true) { values in
            Rectangle()
                .fill(.primary)
                .frame(width: 24, height: 24)
                .scaleEffect(values.scale)
                .rotationEffect(.degrees(values.rotation))
                .offset(x: values.x, y: values.y)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(16, duration: 0.6)
                CubicKeyframe(0, duration: 0.9)
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(8, duration: 0.6)
                CubicKeyframe(16, duration: 0.9)
            }
            KeyframeTrack(\.rotation) {
                CubicKeyframe(90, duration: 0.6)
                CubicKeyframe(200, duration: 0.9)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.6, duration: 0.6)
                CubicKeyframe(1.1, duration: 0.9)
            }
        }
    }
}

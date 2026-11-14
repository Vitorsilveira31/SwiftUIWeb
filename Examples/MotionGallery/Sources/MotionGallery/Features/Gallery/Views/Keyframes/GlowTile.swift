import SwiftUI

/// glow: the whole tile changes colour from green to blue and back, ease, alternating.
/// PhaseAnimator animates the colour change itself, so the view needs no interpolation.
struct GlowTile: View {
    var body: some View {
        PhaseAnimator([false, true]) { onBlue in
            Rectangle()
                .fill(onBlue ? Palette.blue : Palette.green)
        } animation: { _ in
            Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 1)
        }
    }
}

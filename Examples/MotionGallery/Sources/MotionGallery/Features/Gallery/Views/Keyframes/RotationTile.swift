import SwiftUI

/// spin: a 32x12 bar rotated a full turn every 1.2s, linear, forever.
struct RotationTile: View {
    @State private var angle = 0.0

    var body: some View {
        Rectangle()
            .fill(.primary)
            .frame(width: 32, height: 12)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

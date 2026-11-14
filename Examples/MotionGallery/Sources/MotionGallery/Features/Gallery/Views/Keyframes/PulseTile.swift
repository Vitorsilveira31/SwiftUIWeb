import SwiftUI

/// pulse: a 32x32 square scaled 0.5 to 1.2, ease-in-out, alternating forever.
struct PulseTile: View {
    @State private var scale: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(.primary)
            .frame(width: 32, height: 32)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.2
                }
            }
    }
}

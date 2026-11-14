import SwiftUI

/// sweep: a 24x64 gradient bar translated from -24px to 64px, linear, forever.
struct SweepTile: View {
    @State private var offset: CGFloat = -24

    var body: some View {
        LinearGradient(
            colors: [Palette.mist, Palette.slate, Palette.mist],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 24, height: 64)
        .offset(x: offset)
        .frame(width: 64, height: 64, alignment: .leading)
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                offset = 64
            }
        }
    }
}

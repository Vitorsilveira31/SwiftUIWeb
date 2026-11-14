import SwiftUI

/// A grey placeholder with a light highlight that sweeps from -24px to 64px, linear, forever.
/// The end point is fixed at 64px, as in the reference, so wide bars are only partly swept.
struct ShimmerBar: View {
    let corner: CGFloat
    @State private var offset: CGFloat = -24

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Color.gray.opacity(0.2))
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [Palette.mist, Palette.paper, Palette.mist],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .offset(x: offset)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    offset = 64
                }
            }
    }
}

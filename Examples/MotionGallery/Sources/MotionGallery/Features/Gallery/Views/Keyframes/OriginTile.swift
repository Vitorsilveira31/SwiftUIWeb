import SwiftUI

/// origin: an 8px-high bar rotating about its top-left corner, linear, 2s, forever.
struct OriginTile: View {
    @State private var angle = 0.0

    var body: some View {
        Rectangle()
            .fill(.primary)
            .frame(width: 32, height: 8)
            .rotationEffect(.degrees(angle), anchor: .topLeading)
            .frame(width: 64, height: 64, alignment: .topLeading)
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

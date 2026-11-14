import SwiftUI

// A dot marker: a white disc with a blue ring, radius 3 at the vertex.
struct MarkerDot: View {
    let point: CGPoint

    var body: some View {
        Circle()
            .fill(Color(hex: 0xFFFFFF))
            .overlay(Circle().stroke(Color(hex: 0x2563EB), lineWidth: 1.5))
            .frame(width: 6, height: 6)
            .position(x: point.x, y: point.y)
    }
}

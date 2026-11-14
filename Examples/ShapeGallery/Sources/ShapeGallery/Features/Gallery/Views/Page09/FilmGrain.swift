import SwiftUI

// Film grain: a deterministic hash per two-point cell, so the picture is the same every draw.
struct FilmGrain: View {
    var body: some View {
        Canvas { context, _ in
            for row in 0..<36 {
                for column in 0..<18 {
                    let value = Self.noise(Double(column) * 2, Double(row) * 2)
                    let cell = CGRect(x: CGFloat(column) * 2, y: CGFloat(row) * 2, width: 2, height: 2)
                    context.fill(Path(cell), with: .color(Color(white: value)))
                }
            }
        }
        .frame(width: 36, height: 72)
    }

    private static func noise(_ x: Double, _ y: Double) -> Double {
        let s = sin(x * 12.9898 + y * 78.233) * 43758.5453
        return s - floor(s)
    }
}

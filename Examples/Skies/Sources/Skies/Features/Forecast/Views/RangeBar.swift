import SwiftUI

// A capsule track with a gradient segment placed by its fractions of the track.
struct RangeBar: View {
    let start: Double
    let length: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                Capsule()
                    .fill(LinearGradient(colors: [.teal, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * length)
                    .offset(x: geometry.size.width * start)
            }
        }
    }
}

import SwiftUI

/// The ring that pulses at the last point. Paused while frozen, so it holds
/// its phase instead of moving on.
struct CoinPulse: View {
    let id: String
    let hue: Color
    let position: CGPoint
    let frozen: Bool
    let born: Date

    var body: some View {
        TimelineView(.animation(paused: frozen)) { context in
            let ring = PulseKeyframes.ring(
                elapsed: frozen ? nil : context.date.timeIntervalSince(born)
            )
            Circle()
                .stroke(hue, lineWidth: 1.5)
                .frame(width: ring.radius * 2, height: ring.radius * 2)
                .opacity(ring.opacity)
                .position(position)
                .accessibilityIdentifier("ring-\(id)")
        }
    }
}

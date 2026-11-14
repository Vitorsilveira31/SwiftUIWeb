import SwiftUI

/// A 96 x 32 line chart. It draws in once when the row appears; a data change
/// redraws it at once, and freezing shows the finished line and a fixed pulse.
struct CoinSparkline: View {
    let coin: CoinVO
    let frozen: Bool

    @State private var drawn = false
    @State private var born = Date()

    var body: some View {
        let hue = coin.up
            ? Color(red: 0.086, green: 0.639, blue: 0.290)
            : Color(red: 0.863, green: 0.149, blue: 0.149)
        let last = CGPoint(x: 96, y: (1 - (coin.values.last ?? 0)) * 32)

        ZStack {
            SeriesLine(values: coin.values)
                .trim(from: 0, to: frozen || drawn ? 1 : 0)
                .stroke(hue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .accessibilityIdentifier("line-\(coin.id)")

            CoinPulse(id: coin.id, hue: hue, position: last, frozen: frozen, born: born)

            Circle()
                .fill(hue)
                .frame(width: 6, height: 6)
                .position(last)
        }
        .frame(width: 96, height: 32)
        .accessibilityIdentifier("chart-\(coin.id)")
        .onAppear {
            guard !drawn else { return }
            // A row that appears frozen shows its line whole, with no animation.
            if frozen {
                drawn = true
            } else {
                withAnimation(.easeOut(duration: 0.6)) { drawn = true }
            }
        }
    }
}

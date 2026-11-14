import SwiftUI

/// The last price over the change pill, right-aligned.
struct CoinPriceColumn: View {
    let price: String
    let change: String
    let up: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(price)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
            CoinChangePill(change: change, up: up)
        }
    }
}

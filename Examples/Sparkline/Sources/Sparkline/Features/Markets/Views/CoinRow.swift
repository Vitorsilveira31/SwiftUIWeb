import SwiftUI

/// A coin row: badge, name and ticker, chart, then price and change pill.
struct CoinRow: View {
    let coin: CoinVO
    let frozen: Bool

    var body: some View {
        HStack(spacing: 12) {
            CoinBadge(letter: coin.letter, color: coin.color)
            CoinTitle(name: coin.name, ticker: coin.ticker)
                .frame(maxWidth: .infinity, alignment: .leading)
            CoinSparkline(coin: coin, frozen: frozen)
            CoinPriceColumn(price: coin.price, change: coin.change, up: coin.up)
                .frame(width: 104, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("row-\(coin.id)")
    }
}

import SwiftUI

/// The coin's name over its ticker.
struct CoinTitle: View {
    let name: String
    let ticker: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
            Text(ticker)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

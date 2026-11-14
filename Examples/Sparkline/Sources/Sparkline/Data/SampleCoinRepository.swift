import Foundation
import SwiftUI

/// Deterministic sample data: the same coins on every run and every host.
struct SampleCoinRepository: CoinRepository {
    static let count = 40
    static let pointCount = 48

    private static let names = [
        "Voltaris", "Nimbex", "Quorra", "Helion", "Brisk", "Tessel", "Orvane", "Kalypt",
    ]

    private static let colors: [Color] = [
        Color(red: 0.961, green: 0.620, blue: 0.043), // amber
        Color(red: 0.388, green: 0.400, blue: 0.945), // indigo
        Color(red: 0.063, green: 0.725, blue: 0.506), // emerald
        Color(red: 0.937, green: 0.267, blue: 0.267), // red
        Color(red: 0.055, green: 0.647, blue: 0.914), // sky
        Color(red: 0.659, green: 0.333, blue: 0.969), // purple
    ]

    /// Every coin's series, with every third coin moved on by `version` steps.
    /// A tick bumps the version, so only those charts change their data.
    func coins(version: Int) -> [CoinVO] {
        (0..<Self.count).map { coin(index: $0, version: version) }
    }

    private func coin(index: Int, version: Int) -> CoinVO {
        let shift = index % 3 == 0 ? version : 0
        let series = walk(index: index, shift: shift)
        let low = series.min() ?? 0
        let high = series.max() ?? 0
        let span = max(high - low, 1e-9)
        let values = series.map { ($0 - low) / span }

        let first = series[0]
        let last = series[series.count - 1]
        let change = (last / first - 1) * 100
        let name = "\(Self.names[index % Self.names.count])\(index / Self.names.count)"

        return CoinVO(
            id: "c\(index)",
            name: name,
            ticker: String(name.prefix(3)).uppercased(),
            letter: String(name.prefix(1)),
            color: Self.colors[index % Self.colors.count],
            price: String(format: "$%.2f", last),
            change: String(format: "%+.2f%%", change),
            up: change >= 0,
            values: values
        )
    }

    /// A multiplicative random walk. It runs `shift` steps further than it
    /// keeps, so a larger shift is the same series moved forward in time.
    private func walk(index: Int, shift: Int) -> [Double] {
        var random = CoinRandom(seed: (UInt64(index) &* 0x9e37_79b9_7f4a_7c15) ^ 49975)
        var price = 100 + 50 * random.next()
        var path: [Double] = []
        for _ in 0..<(Self.pointCount + shift) {
            price *= 1 + (random.next() - 0.5) * 0.06
            path.append(price)
        }
        return Array(path.dropFirst(shift))
    }
}

import SwiftUI

/// One row of the market list. `values` are the 48 closing prices of the
/// series, normalised to 0 (the series' minimum, drawn at the bottom) through
/// 1 (its maximum, drawn at the top), so the chart maps them to any box.
struct CoinVO: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let ticker: String
    let letter: String
    let color: Color
    let price: String
    let change: String
    let up: Bool
    let values: [Double]
}

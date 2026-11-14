import Foundation

/// A print size the lab offers, with the lab's price for one print.
enum PrintSize: String, CaseIterable, Identifiable, Sendable {
    case fourBySix = "4x6", fiveBySeven = "5x7", eightByTen = "8x10"

    var id: String { rawValue }

    var label: String { rawValue.replacing("x", with: "×") }

    /// The lab's price for one print, in cents.
    var priceCents: Int {
        switch self {
        case .fourBySix: 400
        case .fiveBySeven: 800
        case .eightByTen: 1500
        }
    }
}

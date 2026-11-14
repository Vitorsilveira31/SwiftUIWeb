import SwiftUI

/// A 2x2 square with one white quarter; quarters are numbered clockwise from top-left.
struct QuarterFrame: View {
    let colour: Color
    let whiteQuarter: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                QuarterCell(fill: 0 == whiteQuarter ? .white : colour)
                QuarterCell(fill: 1 == whiteQuarter ? .white : colour)
            }
            HStack(spacing: 0) {
                QuarterCell(fill: 3 == whiteQuarter ? .white : colour)
                QuarterCell(fill: 2 == whiteQuarter ? .white : colour)
            }
        }
    }
}


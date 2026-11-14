import SwiftUI

/// The percentage change on a status-coloured pill. The fills differ by
/// scheme so the ink stays readable in both.
struct CoinChangePill: View {
    let change: String
    let up: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(change)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .background(fill, in: RoundedRectangle(cornerRadius: 4))
    }

    private var fill: Color {
        let dark = colorScheme == .dark
        switch (up, dark) {
        case (true, true): return Color(red: 0.290, green: 0.871, blue: 0.502)
        case (true, false): return Color(red: 0.082, green: 0.502, blue: 0.239)
        case (false, true): return Color(red: 0.973, green: 0.443, blue: 0.443)
        case (false, false): return Color(red: 0.725, green: 0.110, blue: 0.110)
        }
    }
}

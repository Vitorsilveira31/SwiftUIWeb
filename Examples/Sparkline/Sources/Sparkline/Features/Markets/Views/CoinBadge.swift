import SwiftUI

/// The coin's initial in a coloured disc. The ink stays black in both schemes:
/// the data hues are bright enough that black text clears contrast on each.
struct CoinBadge: View {
    let letter: String
    let color: Color

    var body: some View {
        Text(letter)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.black)
            .frame(width: 32, height: 32)
            .background(color, in: Circle())
    }
}

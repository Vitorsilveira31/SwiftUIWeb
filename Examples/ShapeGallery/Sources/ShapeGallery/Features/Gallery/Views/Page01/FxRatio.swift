import SwiftUI

// A 40 x 20 view box at 120 wide is 60 tall: the picture keeps the box's ratio.
struct FxRatio: View {
    var body: some View {
        FixtureTile(name: "fx-ratio") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xFDE68A))
                Circle()
                    .fill(Color(hex: 0xD97706))
                    .frame(width: 48, height: 48)
                    .offset(x: 36, y: 6)
            }
            .frame(width: 120, height: 60, alignment: .topLeading)
        }
    }
}

import SwiftUI

// Paint order: the stroke is drawn first, so the fill covers its inner half.
// The circle's paint server has no fallback that resolves, so the fill is its
// plain colour and it has no stroke.
struct FxOrder: View {
    var body: some View {
        FixtureTile(name: "fx-order") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(Color(hex: 0x78350F), lineWidth: 10)
                    .placed(14, 16, 40, 48)
                Rectangle()
                    .fill(Color(hex: 0xFBBF24))
                    .placed(14, 16, 40, 48)
                Circle()
                    .fill(Color(hex: 0x22C55E))
                    .placed(88 - 22, 40 - 22, 44, 44)
            }
        }
    }
}

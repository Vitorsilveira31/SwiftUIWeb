import SwiftUI

// A lifted square (offset, blur, flood, composite, merge) and a drop shadow.
struct FxShadow: View {
    var body: some View {
        FixtureTile(name: "fx-shadow") {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: 0xFBBF24))
                    .placed(10, 14, 44, 44)
                    .shadow(color: Color(hex: 0x0F172A, opacity: 0.45), radius: 2.5, x: 3, y: 4)
                Circle()
                    .fill(Color(hex: 0x34D399))
                    .placed(68, 16, 40, 40)
                    .shadow(color: Color(hex: 0x7C3AED, opacity: 0.6), radius: 2, x: 2, y: 3)
            }
        }
    }
}

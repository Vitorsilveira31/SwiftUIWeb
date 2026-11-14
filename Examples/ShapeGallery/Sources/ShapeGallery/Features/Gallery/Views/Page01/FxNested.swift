import SwiftUI

// Nested viewports: `slice` clips the first to its box; `visible` lets the second overflow.
struct FxNested: View {
    var body: some View {
        FixtureTile(name: "fx-nested") {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Circle()
                        .fill(Color(hex: 0x14B8A6))
                        .placed(25 - 34, 34 - 34, 68, 68)
                    Rectangle()
                        .fill(Color(hex: 0x0F766E))
                        .placed(-9, 0, 34, 34)
                }
                .frame(width: 50, height: 68, alignment: .topLeading)
                .clipped()
                .offset(x: 6, y: 6)

                Rectangle()
                    .stroke(Color(hex: 0x0F172A), lineWidth: 4)
                    .placed(56, 12, 56, 56)
                Circle()
                    .fill(Color(hex: 0xEAB308))
                    .placed(84 - 16, 40 - 16, 32, 32)
            }
        }
    }
}

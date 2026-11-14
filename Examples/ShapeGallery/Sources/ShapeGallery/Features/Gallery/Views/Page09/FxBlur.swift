import SwiftUI

struct FxBlur: View {
    var body: some View {
        FixtureTile(name: "fx-blur") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0x2563EB))
                    .placed(12, 16, 40, 48)
                    .blur(radius: 4)
                Circle()
                    .fill(Color(hex: 0xF97316))
                    .placed(68, 20, 40, 40)
                    .blur(radius: 1)
            }
        }
    }
}

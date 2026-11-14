import SwiftUI

// CSS filter on boxes: each box and its content are filtered together.
struct FxBoxFilter: View {
    var body: some View {
        FixtureTile(name: "fx-box-filter") {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0xEF4444))
                    .frame(width: 26, height: 26)
                    .grayscale(1)
                    .brightness(0.2)
                Circle()
                    .fill(Color(hex: 0x0EA5E9))
                    .overlay(Circle().stroke(Color(hex: 0x0F172A), lineWidth: 3))
                    .frame(width: 26, height: 26)
                    .blur(radius: 2)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0x22C55E))
                        .frame(width: 26, height: 26)
                    Rectangle()
                        .fill(Color(hex: 0xFDE047))
                        .frame(width: 12, height: 12)
                        .offset(x: 7, y: 7)
                }
                .frame(width: 26, height: 26)
                .shadow(color: Color(hex: 0x0F172A), radius: 2, x: 3, y: 4)
                .hueRotation(.degrees(90))
                .saturation(1.5)
            }
            .padding(.leading, 8)
            .frame(width: 120, height: 80)
        }
    }
}

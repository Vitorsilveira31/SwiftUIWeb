import SwiftUI

// Classes, currentColor, visibility and display.
struct FxStyle: View {
    private let current = Color(hex: 0x0891B2)

    var body: some View {
        FixtureTile(name: "fx-style") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xF97316))
                    .overlay(Rectangle().stroke(Color(hex: 0x7C2D12), lineWidth: 2))
                    .placed(8, 8, 30, 30)
                // The hidden group is skipped; the child that sets visible is drawn.
                Circle()
                    .fill(current)
                    .placed(96 - 14, 23 - 14, 28, 28)
                Rectangle()
                    .fill(current)
                    .overlay(Rectangle().stroke(Color(hex: 0x0F172A), lineWidth: 1))
                    .placed(8, 46, 30, 26)
                Ellipse()
                    .fill(Color(hex: 0xF97316))
                    .overlay(Ellipse().stroke(Color(hex: 0x7C2D12), lineWidth: 2))
                    .placed(96 - 16, 59 - 12, 32, 24)
            }
        }
    }
}

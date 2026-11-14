import SwiftUI

// A dot pattern in user space, clipped to a rect and to a disc; and a checker
// pattern in the rect's own box units.
struct FxPatternDots: View {
    var body: some View {
        FixtureTile(name: "fx-pattern-dots") {
            ZStack(alignment: .topLeading) {
                DotField(region: CGRect(x: 4, y: 4, width: 52, height: 72))
                    .fill(Color(hex: 0x0EA5E9))
                Rectangle()
                    .stroke(Color(hex: 0x0F172A), lineWidth: 1)
                    .placed(4, 4, 52, 72)
                Checkers(origin: CGPoint(x: 64, y: 16), cell: 12, columns: 4, rows: 2)
                    .fill(Color(hex: 0xF43F5E))
                DotField(region: CGRect(x: 0, y: 0, width: 120, height: 80))
                    .fill(Color(hex: 0x0EA5E9))
                    .pictureLayer()
                    .mask {
                        Circle()
                            .fill(.white)
                            .placed(88 - 14, 62 - 14, 28, 28)
                            .pictureLayer()
                    }
                Circle()
                    .stroke(Color(hex: 0x0EA5E9), lineWidth: 1)
                    .placed(88 - 14, 62 - 14, 28, 28)
            }
        }
    }
}

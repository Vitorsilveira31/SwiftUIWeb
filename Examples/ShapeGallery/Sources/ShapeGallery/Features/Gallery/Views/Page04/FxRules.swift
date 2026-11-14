import SwiftUI

// clip-rule evenodd: a ring. The union of two circles, and an intersection with
// the right-hand half, which is a clip that is itself clipped.
struct FxRules: View {
    var body: some View {
        FixtureTile(name: "fx-rules") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0x0EA5E9))
                    .frame(width: 120, height: 80)
                    .clipShape(Ring())
                Rectangle()
                    .fill(Color(hex: 0xEF4444))
                    .frame(width: 120, height: 80)
                    .clipShape(TwoDiscs())
                    .mask(alignment: .topLeading) {
                        Rectangle().placed(60, 0, 40, 80)
                    }
            }
        }
    }
}

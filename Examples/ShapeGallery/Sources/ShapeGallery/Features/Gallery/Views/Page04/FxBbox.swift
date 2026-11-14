import SwiftUI

// Clips on the object bounding box: each rect is cut to the circle inscribed in it.
// The second is turned 20 degrees about its own centre, clipped first.
struct FxBbox: View {
    var body: some View {
        FixtureTile(name: "fx-bbox") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0x16A34A))
                    .placed(8, 10, 60, 60)
                    .clipShape(Circle())
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0xA855F7))
                        .placed(74, 24, 40, 40)
                        .clipShape(Circle())
                }
                .pictureLayer()
                .rotationEffect(.degrees(20), anchor: UnitPoint(x: 94 / 120, y: 44 / 80))
            }
        }
    }
}

import SwiftUI

// CSS properties on SVG rects: the rotation and the scale turn about the fill box's
// centre or top-left corner; `translate` moves after them.
struct FxOrigin: View {
    var body: some View {
        FixtureTile(name: "fx-origin") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xCBD5E1))
                    .placed(15, 25, 30, 30)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0x0EA5E9))
                        .placed(15, 25, 30, 30)
                        .opacity(0.8)
                }
                .pictureLayer()
                .rotationEffect(.degrees(30), anchor: UnitPoint(x: 30 / 120, y: 40 / 80))

                Rectangle()
                    .fill(Color(hex: 0xCBD5E1))
                    .placed(70, 25, 30, 30)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0xF97316))
                        .placed(70, 25, 30, 30)
                        .opacity(0.8)
                }
                .pictureLayer()
                // The transform list (rotate 10deg) first, then scale 0.6, then translate 8px.
                .rotationEffect(.degrees(10), anchor: UnitPoint(x: 70 / 120, y: 25 / 80))
                .scaleEffect(0.6, anchor: UnitPoint(x: 70 / 120, y: 25 / 80))
                .offset(x: 8, y: 8)
            }
        }
    }
}

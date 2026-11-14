import SwiftUI

// An alpha mask keeps the triangle of the rect's top-left half. A translucent grey
// masks by its alpha times its luminance, so it keeps a quarter of its colour.
struct FxMaskAlpha: View {
    var body: some View {
        FixtureTile(name: "fx-mask-alpha") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xF97316))
                    .placed(8, 8, 48, 64)
                    .pictureLayer()
                    .mask {
                        Path { path in
                            path.move(to: CGPoint(x: 8, y: 8))
                            path.addLine(to: CGPoint(x: 56, y: 8))
                            path.addLine(to: CGPoint(x: 8, y: 72))
                            path.closeSubpath()
                        }
                        .fill(.white)
                    }
                Rectangle()
                    .fill(Color(hex: 0x7C3AED))
                    .placed(60, 4, 60, 72)
                    .pictureLayer()
                    .mask {
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.white.opacity(0.25))
                                .placed(64, 8, 52, 64)
                            Rectangle()
                                .fill(.white)
                                .placed(76, 20, 28, 40)
                        }
                        .pictureLayer()
                    }
            }
        }
    }
}

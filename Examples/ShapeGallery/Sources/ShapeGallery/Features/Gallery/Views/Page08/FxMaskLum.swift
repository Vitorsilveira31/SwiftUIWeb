import SwiftUI

// A luminance mask: a white disc with a black hole (the hole is transparent in the
// mask), over a bar chart. The area fades out with a gradient mask.
struct FxMaskLum: View {
    var body: some View {
        FixtureTile(name: "fx-mask-lum") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0x2563EB))
                    .placed(4, 10, 60, 60)
                    .pictureLayer()
                    .mask {
                        ZStack(alignment: .topLeading) {
                            Circle()
                                .fill(.white)
                                .placed(8, 14, 52, 52)
                            Circle()
                                .fill(.black)
                                .placed(24, 30, 20, 20)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                        .pictureLayer()
                    }
                Path { path in
                    path.move(to: CGPoint(x: 68, y: 70))
                    path.addLine(to: CGPoint(x: 68, y: 40))
                    path.addLine(to: CGPoint(x: 80, y: 30))
                    path.addLine(to: CGPoint(x: 92, y: 44))
                    path.addLine(to: CGPoint(x: 104, y: 20))
                    path.addLine(to: CGPoint(x: 116, y: 32))
                    path.addLine(to: CGPoint(x: 116, y: 70))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0x16A34A))
                .mask {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.white, .clear],
                            startPoint: UnitPoint(x: 0.5, y: 20 / 80),
                            endPoint: UnitPoint(x: 0.5, y: 70 / 80)
                        ))
                }
            }
        }
    }
}

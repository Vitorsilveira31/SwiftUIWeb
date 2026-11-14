import SwiftUI

struct FxTransform: View {
    var body: some View {
        FixtureTile(name: "fx-transform") {
            ZStack(alignment: .topLeading) {
                // translate(20, 10) rotate(15): the rotation is applied to the group first.
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0x0EA5E9))
                        .placed(0, 0, 40, 24)
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color(hex: 0xF43F5E))
                            .placed(44, 0, 24, 24)
                    }
                    .pictureLayer()
                    .transformEffect(SVGTransform.rotate(45, about: 56, 12))
                }
                .pictureLayer()
                .transformEffect(SVGTransform.rotate(15))
                .transformEffect(SVGTransform.translate(20, 10))

                // skewX(-20) translate(10 0): the translation first, then the skew.
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0x84CC16))
                        .placed(70, 44, 30, 20)
                }
                .pictureLayer()
                .transformEffect(SVGTransform.translate(10, 0))
                .transformEffect(SVGTransform.skewX(-20))

                // matrix(1 0.2 0 1 0 -6), given directly.
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(hex: 0xA855F7))
                        .placed(10, 50, 30, 20)
                }
                .pictureLayer()
                .transformEffect(CGAffineTransform(a: 1, b: 0.2, c: 0, d: 1, tx: 0, ty: -6))
            }
        }
    }
}

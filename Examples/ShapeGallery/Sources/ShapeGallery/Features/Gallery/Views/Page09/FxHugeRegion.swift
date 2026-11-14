import SwiftUI

// A shadow whose filter region is far larger than the picture, and a mask that is
// white everywhere except a hole: drawn in full, not dropped.
struct FxHugeRegion: View {
    var body: some View {
        FixtureTile(name: "fx-huge-region") {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color(hex: 0xEF4444))
                    .placed(12, 16, 44, 44)
                    .shadow(color: Color(hex: 0x0F172A, opacity: 0.5), radius: 2, x: 2, y: 3)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0x0EA5E9))
                    .placed(66, 14, 48, 52)
                    .pictureLayer()
                    .mask {
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(.white)
                            Circle()
                                .fill(.black)
                                .placed(80, 30, 20, 20)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                        .pictureLayer()
                    }
            }
        }
    }
}

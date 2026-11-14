import SwiftUI

// CSS filter functions on SVG shapes: grey, warmth, hue turns, blur, shadow, and a
// combined chain.
struct FxCss: View {
    var body: some View {
        FixtureTile(name: "fx-css") {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color(hex: 0xEF4444))
                    .placed(6, 8, 28, 28)
                    .grayscale(1)
                Circle()
                    .fill(Color(hex: 0xEF4444))
                    .placed(46, 8, 28, 28)
                    .brightness(0.1)
                    .saturation(1.4)
                Circle()
                    .fill(Color(hex: 0xEF4444))
                    .placed(86, 8, 28, 28)
                    .hueRotation(.degrees(90))
                    .saturation(2)
                Rectangle()
                    .fill(Color(hex: 0x0EA5E9))
                    .placed(8, 46, 24, 24)
                    .blur(radius: 2)
                Rectangle()
                    .fill(Color(hex: 0x0EA5E9))
                    .placed(48, 46, 24, 24)
                    .shadow(color: Color(hex: 0x0F172A), radius: 2, x: 3, y: 3)
                    .colorInvert()
                Rectangle()
                    .fill(Color(hex: 0x0EA5E9))
                    .placed(88, 46, 24, 24)
                    .hueRotation(.degrees(180))
                    .opacity(0.6)
                    .contrast(1.4)
            }
        }
    }
}

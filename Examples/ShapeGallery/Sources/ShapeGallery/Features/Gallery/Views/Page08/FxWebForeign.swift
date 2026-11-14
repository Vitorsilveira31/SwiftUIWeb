import SwiftUI

// A foreign object: HTML inside SVG on the web. Native SwiftUI has no such host, so
// the same box is laid out with SwiftUI views on the blue backdrop.
struct FxWebForeign: View {
    var body: some View {
        FixtureTile(name: "web-foreign") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xE0F2FE))
                VStack(alignment: .leading, spacing: 2) {
                    Text("HTML in SVG")
                        .font(.system(size: 12, weight: .semibold))
                    Text("a box, laid out by the page")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: 0x475569))
                }
                .padding(6)
                .frame(width: 100, height: 60, alignment: .topLeading)
                .background(.white, in: RoundedRectangle(cornerRadius: 6))
                .offset(x: 10, y: 10)
            }
        }
    }
}

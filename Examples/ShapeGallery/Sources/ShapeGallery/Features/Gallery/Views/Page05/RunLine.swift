import SwiftUI

// Three styled pieces of one line of text.
struct RunLine: View {
    var body: some View {
        (Text("BTC ")
            .foregroundStyle(Color(hex: 0x334155))
            + Text("+4.88%")
            .fontWeight(.bold)
            .foregroundStyle(Color(hex: 0x16A34A))
            + Text("↑")
            .foregroundStyle(Color(hex: 0x16A34A))
            .kerning(2)
            .baselineOffset(3))
            .font(.system(size: 13))
    }
}

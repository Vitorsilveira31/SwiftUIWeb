import SwiftUI

// A box's background and the text's colour, both mid-flash.
struct FxBoxcolor: View {
    var body: some View {
        FixtureTile(name: "fx-boxcolor") {
            ZStack {
                Color(hex: 0x0D602C)
                Text("$1,234.56")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x04210F))
            }
            .frame(width: 120, height: 80)
        }
    }
}

import SwiftUI

// A radial shade inside a disc. Used twice on the page, each with its own tint.
struct FxBadge: View {
    let tint: UInt32
    let name: String

    var body: some View {
        FixtureTile(name: name) {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(RadialGradient(
                        colors: [.white, Color(hex: tint)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 32
                    ))
                    .placed(28, 8, 64, 64)
            }
        }
    }
}

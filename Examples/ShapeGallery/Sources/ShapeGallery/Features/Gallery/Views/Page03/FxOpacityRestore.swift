import SwiftUI

// Two groups at half opacity. The second group's fade must not shift the first's bounds.
struct FxOpacityRestore: View {
    var body: some View {
        FixtureTile(name: "fx-opacity-restore") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0x2563EB))
                    .placed(8, 8, 48, 64)
                    .opacity(0.5)
                Rectangle()
                    .fill(LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(hex: 0x30A46C), location: 0),
                            Gradient.Stop(color: Color(hex: 0x30A46C, opacity: 0.2), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .placed(64, 8, 48, 64)
                    .opacity(0.5)
            }
        }
    }
}

import SwiftUI

// A tap in the disc lands on the disc, and the veil above it lets taps through, as
// pointer-events none does.
struct FxHit: View {
    let viewModel: HitTestViewModel

    var body: some View {
        FixtureTile(name: "fx-hit") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: 0xE2E8F0))
                    .frame(width: 120, height: 80)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.send(.picked(.back)) }
                Circle()
                    .fill(Color(hex: viewModel.state.picked == .disc ? 0x16A34A : 0x64748B))
                    .placed(38, 18, 44, 44)
                    .contentShape(Circle())
                    .onTapGesture { viewModel.send(.picked(.disc)) }
                Rectangle()
                    .fill(Color(hex: 0xFFFFFF, opacity: 0.5))
                    .placed(40, 30, 40, 20)
                    .allowsHitTesting(false)
            }
        }
    }
}

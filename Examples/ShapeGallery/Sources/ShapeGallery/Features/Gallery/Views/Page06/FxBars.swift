import SwiftUI

// Three bars in one group: a tap on any bar selects the group. A line beside them
// selects the line.
struct FxBars: View {
    let viewModel: HitTestViewModel

    var body: some View {
        let fill = Color(hex: viewModel.state.picked == .bars ? 0xF59E0B : 0x2563EB)
        FixtureTile(name: "fx-bars") {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(fill)
                    .placed(20, 30, 16, 44)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.send(.picked(.bars)) }
                Rectangle()
                    .fill(fill)
                    .placed(52, 14, 16, 60)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.send(.picked(.bars)) }
                Rectangle()
                    .fill(fill)
                    .placed(84, 44, 16, 30)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.send(.picked(.bars)) }
                linePath
                    .stroke(Color(hex: 0x0F172A), lineWidth: 3)
                    .contentShape(linePath.strokedPath(StrokeStyle(lineWidth: 8)))
                    .onTapGesture { viewModel.send(.picked(.line)) }
            }
        }
    }

    private var linePath: Path {
        Path { path in
            path.move(to: CGPoint(x: 10, y: 70))
            path.addLine(to: CGPoint(x: 60, y: 20))
            path.addLine(to: CGPoint(x: 110, y: 60))
        }
    }
}

import SwiftUI

/// Rotate, reset and undo, in one row.
struct TurnAndUndoRow: View {
    let viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button(Strings.Editor.rotate) {
                viewModel.send(.rotateQuarterTurn)
            }
            .accessibilityLabel(Strings.Editor.rotateLabel)
            .accessibilityIdentifier("rotate")

            Button(Strings.Editor.reset) {
                viewModel.send(.reset)
            }
            .accessibilityLabel(Strings.Editor.resetLabel)
            .accessibilityIdentifier("reset")

            Button(Strings.Editor.undo) {
                viewModel.send(.undo)
            }
            .disabled(!viewModel.state.canUndo)
            .accessibilityIdentifier("undo")
        }
        .buttonStyle(.bordered)
    }
}

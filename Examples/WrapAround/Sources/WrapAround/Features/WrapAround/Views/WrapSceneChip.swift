import SwiftUI

/// One study chip. The selected study is drawn prominent.
struct WrapSceneChip: View {
    let viewModel: WrapAroundViewModel
    let scene: WrapScene

    var body: some View {
        if viewModel.state.scene == scene {
            Button(action: select) {
                Text(scene.label).font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(scene.testId)
        } else {
            Button(action: select) {
                Text(scene.label).font(.caption)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(scene.testId)
        }
    }

    private func select() {
        withAnimation(.smooth) { viewModel.send(.selectScene(scene)) }
    }
}

import SwiftUI

struct StoreZoomRow: View {
    let viewModel: StoreMapViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button(Strings.Stores.zoomOut) {
                viewModel.send(.zoomOut)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.state.zoom.canZoomOut)
            .accessibilityIdentifier("zoom-out")
            Button(Strings.Stores.zoomIn) {
                viewModel.send(.zoomIn)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.state.zoom.canZoomIn)
            .accessibilityIdentifier("zoom-in")
        }
    }
}

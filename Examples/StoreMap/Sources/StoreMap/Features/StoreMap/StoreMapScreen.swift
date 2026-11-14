import SwiftUI

/// The Stores screen: a header, the map, and the controls under it.
struct StoreMapScreen: View {
    @State private var viewModel = StoreMapViewModel()

    var body: some View {
        VStack(spacing: 0) {
            StoreMapHeader(selectedID: viewModel.state.selectedID)
            StoreMapView(viewModel: viewModel)
            StoreMapControls(viewModel: viewModel)
        }
        .accessibilityIdentifier("map-demo")
    }
}

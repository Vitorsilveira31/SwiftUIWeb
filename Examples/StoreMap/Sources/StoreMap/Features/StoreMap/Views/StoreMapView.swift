import MapKit
import SwiftUI

/// The map with one pin per store. Pin taps select a store; camera changes go back to the view model.
struct StoreMapView: View {
    let viewModel: StoreMapViewModel

    var body: some View {
        Map(position: positionBinding, selection: selectionBinding) {
            ForEach(viewModel.state.stores) { store in
                Marker(store.title, systemImage: "storefront", coordinate: store.coordinate)
                    .tag(store.id)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.send(.cameraMoved(context.region))
        }
        .accessibilityIdentifier("map")
        .accessibilityLabel(Strings.Stores.mapLabel)
    }

    private var positionBinding: Binding<MapCameraPosition> {
        Binding(
            get: { viewModel.state.cameraPosition },
            set: { viewModel.send(.setCameraPosition($0)) })
    }

    // Only a pin tap reaches this binding; the buttons change the selection in the view model directly.
    private var selectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.state.selectedID },
            set: { viewModel.send(.selectOnMap($0)) })
    }
}

import MapKit
import Observation
import SwiftUI

@Observable @MainActor
final class StoreMapViewModel {
    struct State {
        static let startCenter = CLLocationCoordinate2D(latitude: 37.7946, longitude: -122.404)

        var stores: [StoreVO] = []
        var selectedID: String?
        var cameraPosition: MapCameraPosition = .region(MapZoom.start.region(center: State.startCenter))
        var zoom: MapZoom = .start
        var center: CLLocationCoordinate2D = State.startCenter
        var picks = 0
    }

    enum Action {
        case selectOnMap(String?)
        case choose(String)
        case cameraMoved(MKCoordinateRegion)
        case setCameraPosition(MapCameraPosition)
        case zoomIn
        case zoomOut
    }

    private(set) var state: State
    private let repository: any StoreRepository

    init(initialState: State = .init(), repository: any StoreRepository = SampleStoreRepository()) {
        self.repository = repository
        self.state = initialState
        if state.stores.isEmpty {
            state.stores = repository.stores()
        }
    }

    func send(_ action: Action) {
        switch action {
        case .selectOnMap(let id):
            guard let id else {
                state.selectedID = nil
                return
            }
            state.selectedID = id
            state.picks += 1
        case .choose(let id):
            guard let store = state.stores.first(where: { $0.id == id }) else { return }
            state.selectedID = id
            state.center = store.coordinate
            state.cameraPosition = .region(state.zoom.region(center: store.coordinate))
        case .cameraMoved(let region):
            state.center = region.center
            state.zoom = MapZoom(longitudeDelta: region.span.longitudeDelta)
        case .setCameraPosition(let position):
            state.cameraPosition = position
        case .zoomIn:
            step(by: 1)
        case .zoomOut:
            step(by: -1)
        }
    }

    /// Zooms one whole level around the centre the map last reported.
    private func step(by delta: Double) {
        state.zoom = state.zoom.stepped(by: delta)
        state.cameraPosition = .region(state.zoom.region(center: state.center))
    }
}
